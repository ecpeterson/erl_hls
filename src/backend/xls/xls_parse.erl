%%%% xls_parse
%%%%
%%%% TODO:
%%%%    + erl_syntax might be a little more ergonomic, have a look

-module(xls_parse).
-moduledoc """
Transforms supported Erlang actor modules into corresponding XLS modules.

## Control flow

Callback bodies may use source-ordered `case` and `if` expressions. Supported
`case` patterns include literals, variables, aliases, tuples, and homogeneous
records. Each clause accepts one guard sequence from the same side-effect-free expression
subset as a callback guard, including comma-separated tests and `andalso` or
`orelse`. A missing match raises a selected `case_clause` or `if_clause`
failure; catch-all clauses are optional. The first selected expression failure
is retained through nested branches and helpers. See `docs/control-flow.md`
for failure reporting and the bounded hardware contract.

A new variable bound in every `case` or `if` arm is available after the
expression, including bindings introduced by case patterns and nested
branches. Each exported value must have the same XLS type in every arm.
Names used only inside an arm stay local and need not agree in type across
arms. Reading or matching a name bound in only some arms is rejected with
the use location and the originating join location. Matching an already-bound
variable checks equality; it never replaces that variable's original value.

Boolean `andalso` and `orelse` expressions use the same conditional lowering
in guards and ordinary bodies. The left operand is evaluated once; only the
selected right operand contributes its value or match failure. Left-operand
bindings remain available afterwards, while right-operand bindings stay local
to that branch. Both operands must have Boolean XLS types; Erlang's more
general non-Boolean right-operand results are not supported. This preserves
selection semantics in generated hardware, not a guarantee that combinational
logic in an unselected branch stops switching.

State-machine entries accept nested `case`/`if` choices of the complete result
or bounded action-list segments, including literal lists, cons tails, and `++`.
Branches may select different ports, schemas, and list lengths. The entry
normalizer packs each selected leaf into one typed outcome before expression
control flow rejoins; the backend commits its data, optional reduction open,
and effects only if the complete callback succeeds. Segments may be named,
aliased, and bound alongside ordinary values through tuple destructuring.
They evaluate at their binding, even if omitted later. See
`docs/entry-outcomes.md` for the bounded source subset.

## Local helpers

Initializers and callbacks may call local pure helpers with concrete `-spec`
types. Only reachable helpers are translated, each as a DSLX function carrying
its result and failure kind. The definition graph must be acyclic; XLS
inlines the calls. Helpers currently have one unguarded clause with distinct
variable parameters (or `_`), and use the same expression subset as callbacks.
See `docs/local-helpers.md` for types, call semantics, and structural limits.

## Wire tags

An actor may declare more than one `-hls_tags([...])` attribute. The compiler
concatenates every block in include-expanded source order. That order is part
of the wire ABI: appending a block preserves existing tag values, while
prepending or moving one can renumber them. Every entry must be a unique atom.
""".
-export([actor_interface/1, actor_interface/2, to_xls/1, to_xls/2]).
%% Internal API shared by the actor-specific lowerers while this module is
%% split into smaller compiler passes.
-export([
    bind/4,
    bitsfromstruct_from_record/1,
    branch_from_clause/4,
    branch_from_clause/6,
    clause_outcome/4,
    failure_expression/1,
    failure_kind/1,
    find_binding/3,
    find_attribute/2,
    find_optional_attribute/2,
    find_tags/1,
    find_function/3,
    find_record/2,
    message_words/2,
    outcome_value/1,
    print/1,
    record_field_name/1,
    record_width/1,
    state/1,
    statement_from_statement/2,
    struct_from_record/1,
    structfrombits_from_record/1,
    validate_record_defaults/1
]).
-export([
    reference/2,
    reference/1,
    instr/2,
    instr/3,
    anonymous_variable/1
]).
-export_type([ir/0, printable/0, static/0, phantom/0]).
-export_type([clause_state/0]).
-compile([export_all, nowarn_export_all]).  % TODO: remove export_all

-include("xls_parse.hrl").

-define(debug(X), begin io:format("~w@~w: ~p~n", [?FUNCTION_NAME, ?LINE, X]), X end).
-define(MAX_PUBLIC_TAGS, 253).  % u8 minus none, error, and actor data

-spec to_xls(string()) -> iolist().
-doc "Transpiles a supported Erlang actor module to a corresponding XLS module.".
to_xls(Filename) ->
    to_xls(Filename, #{shared_service => ordinary}).

-spec to_xls(string(), #{shared_service => ordinary | aggregate_only,
    source_options => [hls_source:option()] | hls_source:context()}) ->
    iolist().
-doc "Transpiles an actor with preprocessing options and a shared-service artifact mode.".
to_xls(Filename, Options0) ->
    Options = validate_xls_options(Options0),
    Mode = maps:get(shared_service, Options),
    {ok, Forms} = parse_file(Filename, maps:get(source_options, Options)),
    case find_optional_attribute(Forms, hls_phases) of
        none when Mode =:= ordinary -> to_xls_gs(Filename, Forms);
        none -> error({unsupported_hls_gs_shared_service, Mode});
        {ok, PhaseNames} ->
            to_xls_statem(Filename, Forms, PhaseNames,
                maps:with([shared_service], Options))
    end.

validate_xls_options(Options) when is_map(Options) ->
    Keys = lists:sort(maps:keys(Options)),
    case Keys -- [shared_service, source_options] of
        [] ->
            case maps:get(shared_service, Options, ordinary) of
                Mode when Mode =:= ordinary; Mode =:= aggregate_only ->
                    #{shared_service => Mode,
                        source_options => maps:get(source_options, Options, [])};
                Mode ->
                    error({invalid_xls_shared_service, Mode})
            end;
        _ ->
            error({invalid_xls_options, Keys})
    end;
validate_xls_options(Options) ->
    error({invalid_xls_options, Options}).

-spec actor_interface(file:filename()) -> map().
-doc "Returns the include-expanded interface inferred for one hls_statem file.".
actor_interface(Filename) ->
    actor_interface(Filename, []).

-spec actor_interface(file:filename(), [hls_source:option()] |
    hls_source:context()) -> map().
-doc "Infers an interface using explicit preprocessing options or a captured context.".
actor_interface(Filename, SourceOptions) ->
    {ok, Forms} = parse_file(Filename, SourceOptions),
    case find_optional_attribute(Forms, hls_phases) of
        {ok, PhaseNames} ->
            xls_statem_lower:interface(Forms, PhaseNames);
        none ->
            error({unsupported_hls_actor_interface, Filename, hls_gs})
    end.

to_xls_gs(Filename, Forms0) ->
    {Forms, Helpers} = xls_helpers:prepare(Forms0,
        [{init, 1}, {handle_call, 2}, {handle_cast, 2}]),
    PublicStructNames = find_tags(Forms),
    StateName = state(Forms),
    StateRecord = find_record(Forms, StateName),
    StateStructName = string:titlecase(lists:delete($_, atom_to_list(StateName))),
    ok = lists:foreach(
        fun(Name) ->
            validate_record_defaults(find_record(Forms, Name))
        end,
        [StateName | PublicStructNames]
    ),
    _ = [message_words(Forms, Name) || Name <- PublicStructNames],

    Emitted = ["// ", Filename, ".x\n",
    """
    // This file is auto-generated by xls_parse. Manual changes will be over-
    // written the next time it is generated. Better to modify the Erlang input.

    """,
    "\n", xls_dslx_imports:emit([axis, hls_failure], xls_dslx_imports:from_forms(Forms)),
    """

    const NOREPLY = u1:0;  // some standard erlang tokens
    const REPLY = u1:1;
    const OK = u1:0;
    const ERROR_FUNCTION_CLAUSE = u32:1;
    const ERROR_REQUEST_LENGTH = u32:3;


    """,
    "const MAX_PAYLOAD = u32:3;\n\n",  % TODO: don't bake this in.
    "pub enum Tag : u8 {\n",
    "  NONE = u8:0,\n",
    [
        ["  ", string:uppercase(atom_to_list(Atom)), " = u8:", integer_to_list(Index), ",\n"]
        ||  {Index, Atom} <- lists:enumerate([error, StateName | PublicStructNames])
    ],
    "}\n\n",
    [
        [struct_from_record(Record), "\n",
         structfrombits_from_record(Record), "\n",
         bitsfromstruct_from_record(Record), "\n"]
        ||  Op <- PublicStructNames,
            Record <- [find_record(Forms, Op)]
    ],
    struct_from_record(StateRecord), "\n",
    structfrombits_from_record(StateRecord), "\n",
    bitsfromstruct_from_record(StateRecord), "\n",
    xls_helpers:emit(Helpers, StateName, #{}),
    xls_gs_lower:initial_state(Forms, StateName),
    """
    proc Service {
      req_in:   chan<axis::Frame> in;
      resp_out: chan<axis::Frame> out;
    """, "\n",
    ["  config(req_in: chan<axis::Frame> in, resp_out: chan<axis::Frame> out) {\n",
     "    (req_in, resp_out)\n",
     "  }\n\n"],
    "  init { initial_state() }\n\n",
    ["  next(state: ", StateStructName, ") {\n",
    """
        let (tok1, frame) = recv(join(), req_in);
    """, "\n",
    ["    let state_record = (Tag::", string:uppercase(atom_to_list(StateName)),
     ", state);\n\n"],
    """
        // cognate to {reply, Reply, State}
        let (resp, new_state) = match frame.header.op as Tag {

    """],
    xls_gs_lower:callback_arms(Forms, StateName),
    """

        };

        let txid = frame.header.txid;
        let resp2 = axis::Frame { header: axis::Header { txid, ..resp.header }, ..resp };
        send_if(tok1, resp_out, resp2.header.op != (Tag::NONE as u8), resp2);
        new_state.1
      }
    }


    """,
    """
    proc Top {
      ext_recv:  chan<axis::Beat> in;
      ext_send:  chan<axis::Beat> out;
    """, "\n",
    ["  config(ext_recv: chan<axis::Beat> in, ext_send: chan<axis::Beat> out) {\n"],
    """
        let (req_p,  req_c ) = chan<axis::Frame, u32:1>("req");
        let (resp_p, resp_c) = chan<axis::Frame, u32:1>("resp");

        spawn axis::Rx(ext_recv, req_p);
        spawn Service(req_c, resp_p);
        spawn axis::Tx(resp_c, ext_send);

        (ext_recv, ext_send)
      }

      init { () }

      next(state: ()) { state }
    }

    """],

    print(Emitted).

to_xls_statem(Filename, Forms, PhaseNames, Options) ->
    xls_statem_lower:lower(Filename, Forms, PhaseNames, Options).

%% We employ a limited IR with three kinds of objects:
%%  + static objects which admit expression in terms of the XLS runtime,
%%  + phantom objects which do not admit expression in terms of the XLS runtime,
%%  + snippets of XLS code.
%%
%% "Closed" IR generally only contains static objects and snippets; phantoms
%% appear temporarily during code generation, e.g., when "passing" the "result"
%% of an Erlang type constructor to XLS's `zero!`.
-type static() :: {static, integer, integer()}.
-type phantom() :: {phantom, type, hls_type:descriptor()}.
-type printable() :: [printable()] | string() | static().
-type ir() :: [ir()] | string() | phantom() | static().

-spec print(printable()) -> iolist().
print(List) when is_list(List) ->
    lists:map(fun print/1, List);
print(Char) when is_integer(Char) ->
    Char;
print({static, integer, Integer}) ->
    integer_to_list(Integer).
%% NOTE: We deliberately fail through on (unprintable!) phantom objects.

-doc """
 
""".
-type clause_state() :: #clause_state{}.

-spec branch_from_clause(
    erl_parse:af_clause(),
    [atom()],
    atom(),
    fun((printable()) -> printable())
) -> {printable(), string()}.
-doc "Processes an Erlang clause from handle_*/2 into XLS.".
branch_from_clause(Clause, ArgVals, StateName, Postprocessor) ->
    ComputeState = lower_clause(Clause, ArgVals, StateName, #{}),
    Failure = [
        "let s = zero!<State>();\n",
        "    (axis::pack(Tag::ERROR as u8, (", failure_kind(ComputeState), ") as u32), ",
        "(Tag::STATE, s))"
    ],
    branch_from_state(ComputeState, Postprocessor, Failure).

branch_from_clause(
    Clause,
    ArgVals,
    StateName,
    Postprocessor,
    Failure,
    EnumAtoms
) ->
    ComputeState = lower_clause(Clause, ArgVals, StateName, EnumAtoms),
    branch_from_state(ComputeState, Postprocessor, Failure).

branch_from_state(ComputeState, Postprocessor, Failure) ->
    OutState = instr(ComputeState, [
        "if (", failure_expression(ComputeState), ") {\n",
        "    ", Failure, "\n",
        "} else {\n",
        "    ", Postprocessor(reference(ComputeState)), "\n",
        "}"
    ]),
    {lists:reverse(OutState#clause_state.statements), OutState#clause_state.reference}.

%% Keep the computed value and its selected failure together. Consumers may
%% commit a compound result only when the whole callback has succeeded.
-spec clause_outcome(erl_parse:af_clause(), [printable()], atom(), map()) ->
    #{body := printable(), result := printable(), failed := printable(), failure := printable()}.
clause_outcome(Clause, ArgVals, StateName, EnumAtoms) ->
    State = lower_clause(Clause, ArgVals, StateName, EnumAtoms),
    #{
        body => lists:reverse(State#clause_state.statements),
        result => reference(State),
        failed => failure_expression(State),
        failure => failure_kind(State)
    }.

lower_clause({clause, _Line, ArgPatterns, _Guards, Body},
        ArgVals, StateName, EnumAtoms) ->
    InjectMatch = fun
        F({{match, LineNo, LHS, RHS}, Arg}) ->
            {match, LineNo, LHS, F({RHS, Arg})};
        F({X, Arg}) ->
            {match, element(2, X), X, Arg}
    end,
    BigBody = case ArgPatterns of
        [{nil, _L}] -> Body;
        _ -> lists:map(InjectMatch, lists:zip(ArgPatterns, ArgVals)) ++ Body
    end,
    lists:foldl(
        fun(Statement, State) ->
            statement_from_statement(Statement, State#clause_state{reference = none})
        end,
        #clause_state{state_name = StateName, enum_atoms = EnumAtoms},
        xls_var_scope:annotate(BigBody)
    ).

-spec statement_from_statement(erl_parse:abstract_expression(), clause_state()) -> clause_state().
-doc """
Main transpiler workhorse.  Recursively converts a complex `erl_parse`
expression into a sequence of simple emitted XLS expressions.
""".
%% Private normalization nodes, introduced after source analysis. Mapping a
%% selected value into a common backend type lets case arms retain different
%% source shapes without moving their computations across a branch boundary.
statement_from_statement({xls_live, _Line, Live, Expression}, State) ->
    Lowered = statement_from_statement(Expression, State#clause_state{live_bindings = Live}),
    Lowered#clause_state{live_bindings = State#clause_state.live_bindings};
statement_from_statement({xls_map, _Line, Expression, Render}, State) ->
    Evaluated = statement_from_statement(Expression, State),
    instr(Evaluated#clause_state{reference = none}, Render(reference(Evaluated)));
statement_from_statement({block, _Line, Expressions}, State) ->
    lower_expression_sequence(Expressions, State);
statement_from_statement(String, State) when is_list(String) ->
    reference(State, String);
statement_from_statement({atom, _L, true}, State) ->
    reference(State, "bool:1");
statement_from_statement({atom, _L, false}, State) ->
    reference(State, "bool:0");
statement_from_statement({atom, _L, Atom}, State = #clause_state{
    enum_atoms = EnumAtoms
}) ->
    reference(
        State,
        maps:get(Atom, EnumAtoms, string:uppercase(atom_to_list(Atom)))
    );
statement_from_statement({var, Line, Name}, State) ->
    case find_binding(Name, Line, State) of
        {ok, Value} -> reference(State, Value);
        error -> error({unbound_xls_variable, Line, Name})
    end;
statement_from_statement({integer, _L, Integer}, State) ->
    reference(State, {static, integer, Integer});
%% Preserve signed literals for width-directed conversions such as wrap/2.
statement_from_statement({op, _L, '-', {integer, _IntegerLine, Integer}}, State) ->
    reference(State, {static, integer, -Integer});
statement_from_statement({op, Line, 'andalso', Left, Right}, State) ->
    xls_case_lower:lower(Line, Left, [
        {clause, Line, [{atom, Line, true}], [], [Right]},
        {clause, Line, [{atom, Line, false}], [], [{atom, Line, false}]}
    ], State);
statement_from_statement({op, Line, 'orelse', Left, Right}, State) ->
    xls_case_lower:lower(Line, Left, [
        {clause, Line, [{atom, Line, true}], [], [{atom, Line, true}]},
        {clause, Line, [{atom, Line, false}], [], [Right]}
    ], State);
statement_from_statement(X, State) when is_tuple(X) andalso op == element(1, X) ->
    [op, _L, Op | Args] = tuple_to_list(X),
    {BwdArgRefs, IntermediateState} = lists:foldl(
        fun(Arg, {ArgRefs, ThisState}) ->
            NewState = statement_from_statement(Arg, ThisState#clause_state{reference = none}),
            {[NewState#clause_state.reference | ArgRefs], NewState}
        end,
        {[], State}, Args
    ),
    instr(IntermediateState, op(Op, lists:reverse(BwdArgRefs)));
statement_from_statement({tuple, _L, Slots}, State) ->
    {BwdReferences, IntermediateState} = lists:foldl(
        fun(Slot, {References, ThisState}) ->
            NewState = statement_from_statement(Slot, ThisState#clause_state{reference = none}),
            {[NewState#clause_state.reference | References], NewState}
        end,
        {[], State}, Slots
    ),
    instr(IntermediateState, ["(", [[Ref, ", "] || Ref <- lists:reverse(BwdReferences)], ")"]);
statement_from_statement({record, _L, NameAtom, Fields}, State) ->
    {BwdAssignments, IntermediateState} = lists:foldl(
        fun({record_field, _1, {atom, _2, FieldAtom}, RHS}, {Assignments, ThisState}) ->
            NewState = statement_from_statement(RHS, ThisState#clause_state{reference = none}),
            {[{FieldAtom, NewState#clause_state.reference} | Assignments], NewState}
        end,
        {[], State}, Fields
    ),
    Assignments = lists:reverse(BwdAssignments),
    SecondState = instr(IntermediateState, [
        string:titlecase(lists:delete($_, atom_to_list(NameAtom))), " {\n",
        [["  ", atom_to_list(FieldAtom), ": ", Reference, ",\n"]
            || {FieldAtom, Reference} <- Assignments],
        "  ..zero!<", string:titlecase(lists:delete($_, atom_to_list(NameAtom))), ">()\n",
        "}"
    ]),
    instr(SecondState, record_value(NameAtom, reference(SecondState), SecondState));
statement_from_statement({record, _L, ToUpdate, NameAtom, UpdateFields}, State) ->
    InputState = statement_from_statement(ToUpdate, State),
    {BwdAssignments, IntermediateState} = lists:foldl(
        fun({record_field, _1, {atom, _2, FieldAtom}, RHS}, {Assignments, ThisState}) ->
            NewState = statement_from_statement(RHS, ThisState#clause_state{reference = none}),
            {[{FieldAtom, NewState#clause_state.reference} | Assignments], NewState}
        end,
        {[], InputState}, UpdateFields
    ),
    Assignments = lists:reverse(BwdAssignments),
    SecondState = instr(IntermediateState, [
        string:titlecase(lists:delete($_, atom_to_list(NameAtom))), " {\n",
            [["  ", atom_to_list(FieldAtom), ": ", Reference, ",\n"]
                || {FieldAtom, Reference} <- Assignments],
        "  ..(", InputState#clause_state.reference, ").1\n",
        "}"
    ]),
    instr(SecondState, record_value(NameAtom, reference(SecondState), SecondState));
statement_from_statement({'if', Line, Clauses}, State) ->
    xls_case_lower:lower_if(Line, Clauses, State);
statement_from_statement({'case', Line, Condition, Clauses}, State) ->
    xls_case_lower:lower(Line, Condition, Clauses, State);
statement_from_statement({xls_helper_call, _Line, Name, Args}, State) ->
    {References, ArgState} = lower_arguments(Args, State),
    CallState = instr(ArgState, [Name, "(", lists:join(", ", References), ")"]),
    outcome_value(CallState);
statement_from_statement({call, _L, MF, Args}, State) ->
    {remote, _1, {atom, _2, Module}, {atom, _3, FAtom}} = MF,
    {References, ArgState} = lower_arguments(Args, State),
    case Module:transpile(FAtom, References, ArgState) of
        X = #clause_state{} -> X;
        X -> instr(ArgState, X)
    end;
statement_from_statement({record_field, _L, Object, _RecordAtom, {atom, _LL, SlotAtom}}, State) ->
    IntermediateState = statement_from_statement(Object, State),
    instr(IntermediateState, [reference(IntermediateState), ".1.", atom_to_list(SlotAtom)]);
statement_from_statement({match, _L, LHS, RHS}, State) ->
    RHSState = statement_from_statement(RHS, State),
    destructure_lhs(LHS, RHSState).

lower_arguments(Args, State) ->
    lists:mapfoldl(fun(Arg, Acc) ->
        Next = statement_from_statement(Arg, Acc#clause_state{reference = none}),
        {reference(Next), Next}
    end, State, Args).

%% A selected outcome contributes one explicit failure kind. Its value
%% and any exported bindings remain separate from that bookkeeping.
-spec outcome_value(clause_state()) -> clause_state().
outcome_value(State) ->
    Value = reference(State),
    reference(add_failure([Value, ".1"], State), [Value, ".0"]).

lower_expression_sequence(Expressions, State0) ->
    lists:foldl(
        fun(Expression, State) ->
            statement_from_statement(
                Expression,
                State#clause_state{reference = none}
            )
        end,
        State0,
        Expressions
    ).

-spec failure_expression(clause_state()) -> printable().
failure_expression(#clause_state{failures = []}) -> "bool:false";
failure_expression(State) ->
    ["(", failure_kind(State), ") != hls_failure::Kind::NONE"].

%% The list is stored in reverse evaluation order. A later failed computation
%% cannot replace an earlier failure, even if its placeholder value is used.
-spec failure_kind(clause_state()) -> printable().
failure_kind(#clause_state{failures = []}) -> "hls_failure::Kind::NONE";
failure_kind(#clause_state{failures = [Last | Earlier]}) ->
    lists:foldl(fun(Failure, Later) ->
        ["hls_failure::first(", Failure, ", ", Later, ")"]
    end, Last, Earlier).

add_match_failure(Predicate, State) ->
    add_failure(["hls_failure::check(", Predicate,
        ", hls_failure::Kind::MATCH_FAILURE)"], State).

add_failure(Failure, State = #clause_state{failures = Failures}) ->
    State#clause_state{failures = [Failure | Failures]}.

%% A partially bound name stays unsafe even if a later expression attempts to
%% bind it again. Keep the originating join for a useful source diagnostic.
-spec find_binding(atom(), erl_anno:location(), clause_state()) ->
    {ok, printable()} | error.
find_binding(Name, Line, #clause_state{bindings = Bindings, unsafe_bindings = Unsafe}) ->
    case maps:find(Name, Unsafe) of
        {ok, Origin} -> error({unsafe_xls_variable, Line, Name, Origin});
        error -> maps:find(Name, Bindings)
    end.

-spec bind(atom(), erl_anno:location(), printable(), clause_state()) -> clause_state().
bind(Name, Line, Value, State) ->
    Previous = find_binding(Name, Line, State),
    {Emitted, Named} = uniquify(State, Name),
    Bound = instr(Named, Emitted, Value),
    Next = case Previous of
        {ok, Existing} -> add_match_failure([Existing, " != ", Emitted], Bound);
        error -> Bound#clause_state{bindings = (Bound#clause_state.bindings)#{Name => Emitted}}
    end,
    reference(Next, Value).

-spec record_value(atom(), ir(), clause_state()) -> iolist().
record_value(NameAtom, Struct, #clause_state{state_name = NameAtom}) ->
    ["(Tag::", string:uppercase(atom_to_list(NameAtom)), ", ", Struct, ")"];
record_value(NameAtom, Struct, _State) ->
    [
        "(Tag::", string:uppercase(atom_to_list(NameAtom)), ", ", Struct, ", ",
        "bits_from_", lists:delete($_, atom_to_list(NameAtom)), "(", Struct, "))"
    ].

-spec destructure_lhs(erl_parse:af_pattern(), clause_state()) -> clause_state().
-doc """
Converts an assignment from an opaque RHS to a structured LHS into a sequence of
accessors into the RHS being assigned to slots inside of the LHS.
""".
destructure_lhs({var, _L, '_'}, State) ->
    State;
destructure_lhs({var, Line, Name}, State) ->
    bind(Name, Line, reference(State), State);
destructure_lhs({record, _L, _Atom, Slots}, State) ->
    RecordRef = State#clause_state.reference,
    IntermediateState = lists:foldl(
        fun({record_field, _1, {atom, _2, SlotAtom}, LHS}, ThisState) ->
            Slot = atom_to_list(SlotAtom),
            Substate = ThisState#clause_state{reference = [RecordRef, ".", Slot]},
            destructure_lhs(LHS, Substate)
        end,
        State, Slots
    ),
    IntermediateState#clause_state{reference = RecordRef};
destructure_lhs({tuple, _L, Slots}, State) ->
    TupleRef = State#clause_state.reference,
    IntermediateState = lists:foldl(
        fun({Index, LHS}, ThisState) ->
            Substate = ThisState#clause_state{
                reference = [TupleRef, ".", integer_to_list(Index)]
            },
            destructure_lhs(LHS, Substate)
        end,
        State,
        lists:enumerate(0, Slots)
    ),
    IntermediateState#clause_state{reference = TupleRef};
%% constant cases
destructure_lhs({atom, _L, Atom}, State) when Atom == true orelse Atom == false ->
    add_match_failure([reference(State), " != bool:", atom_to_list(Atom)], State).
%% TODO: badmatch on other constants

%%%
%%% Erlang record / XLS struct munging.
%%%
%%% XLS does not support `(struct) as bits` and `(bits) as struct` conversions,
%%% so we have to emit manual un/packers.
%%% TODO: Give selected public message structs and packers a cross-module DSLX
%%% interface so topology startup code can emit typed constructors instead of
%%% opaque prepacked literals.
%%%

-spec struct_from_record(erl_parse:af_record_decl()) -> iolist().
-doc "Translates an Erlang record definition to an XLS struct definition.".
struct_from_record(RecordForm) ->
    {attribute, _L, record, {NameAtom, Fields}} = RecordForm,
    Name = lists:delete($_, atom_to_list(NameAtom)),
    StructName = string:titlecase(Name),
    ["pub struct ", StructName, " {\n",
        [io_lib:format("  ~w : ~s,~n", [
                element(3, element(3, Field)),
                hls_type:print_type(hls_type:descriptor(Type))
            ])
            ||  {typed_record_field, Field, Type} <- Fields
        ],
    "}\n"].

-spec structfrombits_from_record(erl_parse:af_record_decl()) -> iolist().
-doc "Builds an XLS-side unpacker for the Erlang record definition.".
structfrombits_from_record(RecordForm) ->
    {attribute, _L, record, {NameAtom, Fields}} = RecordForm,
    Name = lists:delete($_, atom_to_list(NameAtom)),
    StructName = string:titlecase(Name),
    ["pub fn ", string:lowercase(StructName), "_from_bits<N: u32>(raw: bits[N]) -> ", StructName, " {\n",
    "  ", StructName, " {\n",
    lists:reverse(element(1, lists:foldl(
        fun(
            {typed_record_field, Field, Type},
            {Body, Offset}
        ) ->
            Slot = record_field_name(Field),
            Descriptor = hls_type:descriptor(Type),
            NextOffset = Offset + hls_type:width(Descriptor),
            Line = io_lib:format(
                "    ~w: raw[~w:~w] as ~s,~n",
                [
                    Slot,
                    Offset,
                    NextOffset,
                    hls_type:print_type(Descriptor)
                ]
            ),
            {[Line | Body], NextOffset}
        end,
        {[], 0}, Fields
    ))),
    "  }\n",
    "}\n"].

-spec bitsfromstruct_from_record(erl_parse:af_record_decl()) -> iolist().
-doc "Builds an XLS-side packer for the Erlang record definition.".
bitsfromstruct_from_record(_RecordForm = {attribute, _L, record, {NameAtom, Fields}}) ->
    Name = lists:delete($_, atom_to_list(NameAtom)),
    StructName = string:titlecase(Name),
    ["pub fn bits_from_", string:lowercase(StructName), "(s: ", StructName, ") -> bits[bit_count<", StructName, ">()] {\n",
        ["  ", lists:foldl(
            fun({typed_record_field, Field, Type}, Body) ->
                Slot = record_field_name(Field),
                Line = io_lib:format("(s.~w as bits[~w]) ++ ", [Slot, hls_type:width(hls_type:descriptor(Type))]),
                [Line | Body]  % implicit lists:reverse with this join order
            end,
            [" zero!<bits[0]>()\n"], Fields
        )],
    "}\n"].

-spec message_words([erl_parse:abstract_form()], atom()) -> 0..3.
message_words(Forms, Name) ->
    Width = record_width(find_record(Forms, Name)),
    case Width rem 32 of
        0 when Width =< 96 -> Width div 32;
        0 -> error({xls_message_too_wide, Name, Width, 96});
        _ -> error({xls_message_not_word_aligned, Name, Width, 32})
    end.

-spec record_width(erl_parse:af_record_decl()) -> non_neg_integer().
-doc "Calculates the packed width of an Erlang record's XLS struct.".
record_width({attribute, _L, record, {_NameAtom, Fields}}) ->
    lists:sum([
        hls_type:width(hls_type:descriptor(Type))
        || {typed_record_field, _Field, Type} <- Fields
    ]).

-spec record_field_name(erl_parse:af_record_field()) -> atom().
-doc "Extracts a field name from record declarations with or without a default.".
record_field_name({record_field, _L, {atom, _AtomL, Name}}) ->
    Name;
record_field_name({record_field, _L, {atom, _AtomL, Name}, _Default}) ->
    Name.

-spec validate_record_defaults(erl_parse:af_record_decl()) -> ok.
-doc """
Requires every field in a translated record to use the type-directed
`hls_type:zero()` marker, keeping Erlang defaults consistent with XLS `zero!`.
""".
validate_record_defaults({attribute, _L, record, {RecordName, Fields}}) ->
    lists:foreach(
        fun({
            typed_record_field,
            {record_field, Line, {atom, _AtomLine, FieldName}, Default},
            _Type
        }) ->
            case is_zero_default(Default) of
                true -> ok;
                false ->
                    error({invalid_hls_record_default, RecordName, FieldName, Line})
            end;
           ({
            typed_record_field,
            {record_field, Line, {atom, _AtomLine, FieldName}},
            _Type
        }) ->
            error({missing_hls_record_default, RecordName, FieldName, Line});
           (Field) ->
            error({untyped_xls_record_field, RecordName, Field})
        end,
        Fields
    ),
    ok.

-spec is_zero_default(erl_parse:abstract_expr()) -> boolean().
-doc "Recognizes the type-directed zero marker in a record declaration.".
is_zero_default({
    call,
    _Line,
    {remote, _RemoteLine, {atom, _ModuleLine, hls_type}, {atom, _NameLine, zero}},
    []
}) ->
    true;
is_zero_default(_Default) ->
    false.

%%%
%%% clause_state utilities
%%%

-spec anonymous_variable(clause_state()) -> {clause_state(), VarName :: string()}.
anonymous_variable(State = #clause_state{anonymous_counter = Counter}) ->
    {State#clause_state{anonymous_counter = Counter + 1}, [$_ | integer_to_list(Counter)]}.

-spec uniquify(clause_state(), atom() | string()) ->
    {string(), clause_state()}.
-doc "Rewrites NameAtom in a way that guarantees no collision with previous uses.".
uniquify(State, NameAtom) when is_atom(NameAtom) ->
    Name = atom_to_list(NameAtom),
    uniquify(State, Name);
uniquify(State = #clause_state{named_counters = Counters}, Name) ->
    Counter = maps:get(Name, Counters, 0) + 1,
    NamedCounters = Counters#{Name => Counter},
    NewName = Name ++ [$_ | integer_to_list(Counter)],
    {NewName, State#clause_state{named_counters = NamedCounters}}.

-spec reference(clause_state()) -> none | ir().
reference(ClauseState) ->
    ClauseState#clause_state.reference.

-spec reference(clause_state(), ir()) -> clause_state().
reference(ClauseState, Reference) ->
    ClauseState#clause_state{reference = Reference}.

-spec instr(clause_state(), ir()) -> clause_state().
instr(#clause_state{anonymous_counter = Counter} = ClauseState, Expr) ->
    instr(
        ClauseState#clause_state{anonymous_counter = Counter + 1},
        [$_ | integer_to_list(Counter)],
        Expr
    ).

-spec instr(clause_state(), ir(), ir()) -> clause_state().
instr(ClauseState, Place, Expr) ->
    % TODO: we should admit structured `Place`s in reference and print them in statements
    ClauseState#clause_state{
        reference = Place,
        statements = [["let ", Place, " = ", Expr, ";\n"] | ClauseState#clause_state.statements]
    }.

%%%
%%% Dictionaries for built-in calls
%%%

-spec op(Op :: atom(), Args :: [any()]) -> iolist().
-doc "Translates a built-in Erlang op to an XLS op.".
op('+', [Left, Right]) -> [Left, " + ", Right];
op('-', [Left, Right]) -> [Left, " - ", Right];
op('*', [Left, Right]) -> [Left, " * ", Right];
op('div', [Left, Right]) -> [Left, " / ", Right];
op('bsl', [Left, Right]) -> [Left, " << ", Right];
op('bsr', [Left, Right]) -> [Left, " >> ", Right];
op('band', [Left, Right]) -> [Left, " & ", Right];
op('bor', [Left, Right]) -> [Left, " | ", Right];
op('bxor', [Left, Right]) -> [Left, " ^ ", Right];
op('bnot', [Operand]) -> ["!", Operand];
op('not', [Operand]) -> ["!", Operand];
op('<', [Left, Right]) -> [Left, " < ", Right];
op('=<', [Left, Right]) -> [Left, " <= ", Right];
op('>', [Left, Right]) -> [Left, " > ", Right];
op('>=', [Left, Right]) -> [Left, " >= ", Right];
op('=:=', [Left, Right]) -> [Left, " == ", Right];
op('=/=', [Left, Right]) -> [Left, " != ", Right].

%%%
%%% Search / selection tools
%%%

-spec state([erl_parse:abstract_form()]) -> atom().
-doc "Finds the record name which carries an actor's rich data value.".
state(Forms) ->
    case find_optional_attribute(Forms, hls_data) of
        {ok, DataAtom} ->
            DataAtom;
        none ->
            inferred_state(Forms)
    end.

inferred_state(Forms) ->
    InitSpec = find_spec(Forms, init, 1),
    {attribute, _1, spec, {
        {init, 1},
        [{type, _2, 'fun', [
            _3,
            {type, _4, record, [{atom, _5, StateAtom}]}
        ]}]
    }} = InitSpec,
    StateAtom.

-spec find_record([erl_parse:abstract_form()], atom()) -> erl_parse:af_record_decl().
-doc "Find the record definition with the indicated name from the set of Forms.".
find_record(Forms, Name) ->
    {value, Record} = lists:search(
        fun ({attribute, _L, record, {NameAtom, _Fields}}) -> NameAtom == Name;
            (_) -> false
        end, Forms
    ),
    Record.

-spec find_function([erl_parse:abstract_form()], atom(), integer()) -> erl_parse:af_clause_seq().
-doc "Find the function definition with the indicated F/A from the set of Forms.".
find_function(Forms, F, A) ->
    {value, {function, _LineNo, F, A, Clauses}} = lists:search(
        fun ({function, _LineNo, FF, AA, _Clauses}) ->
                F == FF andalso A == AA;
            (_) -> false
        end,
        Forms
    ),
    Clauses.

-spec find_attribute([erl_parse:abstract_form()], atom()) -> erl_parse:af_wild_attribute().
-doc "Finds the attribute with the indicated name from the set of Forms.".
find_attribute(Forms, Atom) ->
    {value, {attribute, _L, _A, Value}} = lists:search(
        fun ({attribute, _L, A, _Value}) -> A == Atom;
            (_) -> false
        end,
        Forms
    ),
    Value.

-spec find_tags([erl_parse:abstract_form()]) -> [atom()].
-doc "Collects all hls_tags attributes in include-expanded source order.".
find_tags(Forms) ->
    Fragments = [
        {Line, Value}
        || {attribute, Line, hls_tags, Value} <- Forms
    ],
    case Fragments of
        [] ->
            error({missing_hls_attribute, hls_tags});
        _ ->
            Tags = lists:append([
                validate_tag_fragment(Line, Value)
                || {Line, Value} <- Fragments
            ]),
            case duplicate_tags(Tags) of
                [] -> validate_tag_count(Tags);
                Duplicates -> error({duplicate_hls_tags, Duplicates})
            end
    end.

validate_tag_count(Tags) when length(Tags) =< ?MAX_PUBLIC_TAGS ->
    Tags;
validate_tag_count(Tags) ->
    error({too_many_hls_tags, length(Tags), ?MAX_PUBLIC_TAGS}).

validate_tag_fragment(Line, Tags) when is_list(Tags) ->
    case lists:all(fun is_atom/1, Tags) of
        true -> Tags;
        false -> error({invalid_hls_tags, Line, Tags})
    end;
validate_tag_fragment(Line, Value) ->
    error({invalid_hls_tags, Line, Value}).

duplicate_tags(Tags) ->
    duplicate_tags(Tags, #{}, []).

duplicate_tags([], _Counts, Duplicates) ->
    lists:reverse(Duplicates);
duplicate_tags([Tag | Rest], Counts, Duplicates) ->
    Count = maps:get(Tag, Counts, 0),
    NextDuplicates = case Count of
        1 -> [Tag | Duplicates];
        _ -> Duplicates
    end,
    duplicate_tags(Rest, Counts#{Tag => Count + 1}, NextDuplicates).

-spec find_optional_attribute([erl_parse:abstract_form()], atom()) ->
    none | {ok, term()}.
find_optional_attribute(Forms, Atom) ->
    case lists:search(
        fun
            ({attribute, _Line, Name, _Value}) -> Name =:= Atom;
            (_Form) -> false
        end,
        Forms
    ) of
        {value, {attribute, _Line, Atom, Value}} -> {ok, Value};
        false -> none
    end.

-spec find_spec([erl_parse:abstract_form()], atom(), integer()) -> erl_parse:af_function_spec().
-doc "Finds the function type declaration with the given F/A from the set of Forms.".
find_spec(Forms, F, A) ->
    {value, Spec} = lists:search(
        fun ({attribute, _LineNo, spec, {{FF, AA}, _Data}}) ->
                F == FF andalso A == AA;
            (_) -> false
        end,
        Forms
    ),
    Spec.

%%%
%%% Other utilities
%%%

-spec parse_file(string()) -> {ok, [erl_parse:abstract_form()]}.
-doc "Helper routine for reading an entire .erl source file into memory.".
parse_file(Filename) ->
    parse_file(Filename, []).

parse_file(Filename, Context) when is_map(Context) ->
    {ok, hls_source:read(Filename, Context)};
parse_file(Filename, Options) ->
    Context = hls_source:options(Filename, Options),
    #{includes := Includes} = Context,
    {ok, hls_source:read(Filename,
        Context#{includes := Includes ++ application_includes()})}.

application_includes() ->
    case code:lib_dir(erl_hls) of
        {error, bad_name} ->
            [filename:absname("include")];
        Application ->
            [filename:join(Application, "include")]
    end.
