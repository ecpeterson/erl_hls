-module(xls_gs_deferred).
-moduledoc "Lowers bounded server callbacks into a worker for the static retained-reply driver.".
-export([emit/2]).

-doc "Emits checked callbacks, finite continuations and the standard frame/beat service wrappers.".
-spec emit(file:filename(), [hls_source:form()]) -> iolist().
emit(Filename, Forms0) ->
    ok = xls_names:actor(Forms0, hls_gs),
    {Source, Sites} = xls_failure_sites:prepare(Forms0),
    {Forms, Helpers} = xls_helpers:prepare(Source,
        [{init, 1}, {handle_call, 3}, {handle_cast, 2}, {handle_continue, 2}]),
    #{calls := Calls, pending_calls := N, continuations := Names} =
        hls_service_contract:from_forms(Forms),
    StateName = xls_parse:state(Forms),
    Tags = [error, StateName | xls_parse:find_tags(Forms)],
    Enum = maps:from_list([{Name, ["u8:", integer_to_list(I)]} || {I, Name} <- lists:enumerate(1, Names)]),
    Width = xls_parse:record_width(xls_parse:find_record(Forms, StateName)),
    Records = [xls_parse:find_record(Forms, Name) || Name <- tl(Tags)],
    [xls_parse:validate_record_defaults(R) || R <- Records],
    [xls_parse:message_words(Forms, Name) || Name <- xls_parse:find_tags(Forms)],
    Mask = lists:sum([1 bsl I || {I, Name} <- lists:enumerate(1, Tags), maps:is_key(Name, Calls)]),
    Body = ["// ", Filename, " - generated bounded server.\n",
     xls_dslx_imports:emit([axis, hls_bits, hls_failure, hls_server], xls_dslx_imports:from_forms(Forms)),
     "\npub enum Tag : u8 { NONE = 0,\n",
     [["  ", xls_names:enum_member(Name), " = ", integer_to_list(I), ",\n"]
         || {I, Name} <- lists:enumerate(1, Tags)], "}\n",
     [[xls_parse:struct_from_record(R), "\n", xls_parse:structfrombits_from_record(R), "\n",
       xls_parse:bitsfromstruct_from_record(R), "\n"] || R <- Records],
     "const STATE_BITS = u32:", integer_to_list(Width), ";\n",
     "type Invocation = hls_server::Invocation<STATE_BITS>;\n",
     "type Outcome = hls_server::Outcome<STATE_BITS>;\n",
     allowed(Calls), xls_helpers:emit(Helpers, StateName, Enum),
     xls_gs_lower:initial_state(Forms, StateName),
     "fn dispatch(inv: Invocation) -> Outcome {\n",
     "  let state_record = (Tag::", xls_names:enum_member(StateName), ", ",
     xls_names:record_codec(StateName), "_from_bits(inv.state));\n",
     "  if inv.initialize { Outcome { state: bits_from_", xls_names:record_codec(StateName),
     "(initial_state()), reply_allowed: true, ..zero!<Outcome>() } }\n",
     "  else if inv.continuation != u8:0 {\n",
     continuation(Forms, StateName, Enum), "\n  } else { match inv.frame.header.op as Tag {\n",
     [arm(Kind, Group, Forms, StateName, Enum) || Kind <- [call, cast],
         Group <- hls_service_contract:groups(Forms, callback(Kind))],
     "_ => ", failure("u32:1"), ",\n  } }\n}\n",
     service(N, Mask),
     "pub proc Top {\n",
     " config(input: chan<axis::Beat> in, output: chan<axis::Beat> out) {\n",
     "  let (req_p, req_c) = chan<axis::Frame, u32:1>(\"request\");\n",
     "  let (resp_p, resp_c) = chan<axis::Frame, u32:1>(\"reply\");\n",
     "  spawn axis::Rx(input, req_p); spawn Service(req_c, resp_p); spawn axis::Tx(resp_c, output); ()\n",
     " }\n init { () }\n next(state: ()) { state }\n}\n"],
    xls_failure_sites:emit(Sites, Body).

%% Callback names share the contract's record grouping.
-spec callback(call | cast) -> atom().
callback(call) -> handle_call;
callback(cast) -> handle_cast.

%% The handle's tag is checked only when its complete token still owns a slot.
-spec allowed(#{atom() => [atom()]}) -> iolist().
allowed(Calls) ->
    ["fn reply_allowed(from: u64, tag: u8) -> bool {\n", "  ",
     case maps:to_list(Calls) of
         [] -> "false";
         Entries -> lists:join(" ||\n  ", [["((from as u8) == Tag::", xls_names:enum_member(Request),
             " as u8 && (", lists:join(" || ", [["tag == Tag::", xls_names:enum_member(R), " as u8"]
                 || R <- Replies]), "))"] || {Request, Replies} <- Entries])
     end, "\n}\n"].

%% Validate input length before any callback or application-state mutation.
-spec arm(call | cast, {atom(), [erl_parse:abstract_clause()]}, [hls_source:form()], atom(), map()) -> iolist().
arm(Kind, {Tag, Clauses}, Forms, StateName, Enum) ->
    Raw = "request",
    Record = xls_pattern_lower:record_argument(Tag, Raw,
        ["(Tag::", xls_names:enum_member(Tag), ", request, bits_from_", xls_names:record_codec(Tag), "(request))"]),
    Args = [Record] ++ case Kind of call -> [xls_pattern_lower:value_argument("inv.from")]; cast -> [] end
        ++ [state_argument(StateName)],
    ["Tag::", xls_names:enum_member(Tag), " => {\n",
     " if inv.frame.header.payload_words != u8:", integer_to_list(xls_parse:message_words(Forms, Tag)),
     " { ", failure("u32:3"), " } else {\n",
     " let request = ", xls_names:record_codec(Tag), "_from_bits(inv.frame.payload);\n",
     lower(Clauses, Args, Kind, StateName, Enum), "\n }\n},\n"].

%% Continuation names are finite atoms; all operation arguments live in application state.
-spec continuation([hls_source:form()], atom(), map()) -> iolist().
continuation(Forms, StateName, Enum) ->
    Clauses = lists:append([C || {function, _, handle_continue, 2, C} <- Forms]),
    lower(Clauses, [xls_pattern_lower:value_argument("inv.continuation"), state_argument(StateName)],
        continue, StateName, Enum).

%% The expression compiler keeps the state record's tag while projecting its concrete data.
-spec state_argument(atom()) -> xls_pattern_lower:argument().
state_argument(Name) -> xls_pattern_lower:record_argument(Name, "state_record.1", "state_record").

%% Normalize each selected result before joining differently shaped Erlang alternatives.
-spec lower([erl_parse:abstract_clause()], [xls_pattern_lower:argument()], call | cast | continue, atom(), map()) -> iolist().
lower(Clauses, Args, Kind, StateName, Enum) ->
    Normalized = [xls_callback_result:map_actions(C, fun(R) -> result(R, Kind, Enum) end) || C <- Clauses],
    {Body, Value} = xls_callback_lower:lower(Normalized, Args, StateName,
        fun(R) -> ["Outcome { reply: ", R, ".0, from: ", R, ".1, state: bits_from_",
            xls_names:record_codec(StateName), "(", R, ".2.1), continuation: ", R,
            ".3, reply_allowed: ", R, ".4, error: u32:0 }"] end,
        failure("u32:1"), fun(Code) -> failure(["hls_failure::kind(", Code, ") as u32"]) end, Enum),
    [xls_parse:print(Body), xls_parse:print(Value)].

%% A callback fault preserves its input data and emits no successful action.
-spec failure(iodata()) -> iolist().
failure(Code) -> ["Outcome { state: inv.state, error: ", Code, ", ..zero!<Outcome>() }"] .

%% Source result forms deliberately bound each step to one reply and one continuation.
-spec result(term(), call | cast | continue, map()) -> term().
result({tuple, L, [{atom, _, reply}, Reply, State]}, call, Enum) ->
    mapped(L, State, {immediate, Reply}, none, Enum);
result({tuple, L, [{atom, _, reply}, Reply, State, {tuple, _, [{atom, _, continue}, {atom, _, Name}]}]}, call, Enum) ->
    mapped(L, State, {immediate, Reply}, Name, Enum);
result({tuple, L, [{atom, _, noreply}, State]}, _Kind, Enum) ->
    mapped(L, State, none, none, Enum);
result({tuple, L, [{atom, _, noreply}, State, {tuple, _, [{atom, _, continue}, {atom, _, Name}]}]}, _Kind, Enum) ->
    mapped(L, State, none, Name, Enum);
result({tuple, L, [{atom, _, noreply}, State, Actions]}, _Kind, Enum) ->
    {Reply, Continue} = actions(Actions),
    mapped(L, State, Reply, Continue, Enum);
result(Result, _, _) -> error({invalid_hls_server_result, Result}).

%% Accept a literal bounded action list after callback-result binding normalization.
-spec actions(term()) -> {none | {retained, term(), term()}, atom()}.
actions({nil, _}) -> {none, none};
actions({cons, _, {tuple, _, [{atom, _, continue}, {atom, _, Name}]}, {nil, _}}) -> {none, Name};
actions({cons, _, {tuple, _, [{atom, _, reply}, From, Reply]}, Tail}) ->
    {none, Continue} = actions(Tail),
    {{retained, From, Reply}, Continue};
actions(Actions) -> error({invalid_hls_server_actions, Actions}).

%% Preserve tuple/list field evaluation order (including failure precedence), then form the common outcome.
-spec mapped(term(), term(), term(), atom(), map()) -> term().
mapped(Line, State, Reply, Continue, Enum) ->
    Continuation = case Continue of none -> "u8:0"; _ -> maps:get(Continue, Enum) end,
    {Fields, StateField, ReplyField, Handle} = case Reply of
        none -> {[State], "value.0", none, "u64:0"};
        {immediate, Value} -> {[Value, State], "value.1", "value.0", "inv.from"};
        {retained, From, Value} -> {[State, From, Value], "value.0", "value.2", "(value.1 as u64)"}
    end,
    {xls_map, Line, {tuple, Line, Fields}, fun(R) ->
        ["{ let value = ", R, ";\n",
         case ReplyField of none -> []; _ ->
             ["let reply = axis::pack(", ReplyField, ".0 as u8, hls_bits::frame_payload(", ReplyField, ".2));\n"] end,
         "(", case ReplyField of none -> "zero!<axis::Frame>()"; _ -> "reply" end,
         ", ", Handle, ", ", StateField, ", ", Continuation, ", ",
         case ReplyField of none -> "true"; _ -> ["reply_allowed(", Handle, ", reply.header.op)"] end,
         ") } "]
    end}.

%% Keep callback execution separate from the maintained static ownership/scheduling driver.
-spec service(pos_integer(), non_neg_integer()) -> iolist().
service(N, Mask) ->
    Masks = lists:join(", ", [["u64:", integer_to_list((Mask bsr Shift) band ((1 bsl 64)-1))]
        || Shift <- [0, 64, 128, 192]]),
    ["proc Worker {\n input: chan<Invocation> in; output: chan<Outcome> out;\n",
     " config(input: chan<Invocation> in, output: chan<Outcome> out) { (input, output) }\n",
     " init { () }\n next(state: ()) { let (tok, request) = recv(join(), input);\n",
     "  send(tok, output, dispatch(request)); state }\n}\n",
     "pub proc Service {\n config(input: chan<axis::Frame> in, output: chan<axis::Frame> out) {\n",
     " let (invoke_p, invoke_c) = chan<Invocation, u32:1>(\"invoke\");\n",
     " let (outcome_p, outcome_c) = chan<Outcome, u32:1>(\"outcome\");\n",
     " spawn Worker(invoke_c, outcome_p);\n",
     " spawn hls_server::Driver<STATE_BITS, u32:", integer_to_list(N), ", ", Masks,
     ">(input, output, invoke_p, outcome_c); ()\n",
     " }\n init { () }\n next(state: ()) { state }\n}\n"].
