%%%% xls_gs_lower
%%%%
%%%% Lowers hls_gs initialization and groups callback clauses by wire tag.
%%%% Callback lowering is shared by the immediate and retained-call server emitters.

-module(xls_gs_lower).
-moduledoc "Lowers server initialization and ordered call/cast callback families for xls_gs_immediate and xls_gs_deferred. It adapts the server result contract to shared xls_init and xls_callback_lower fragments; the enclosing server renderer supplies service storage, channels and final failure allocation.".

%% Lower the server's compile-time initializer.
-export([initial_state/2]).
%% Build call/cast dispatch fragments under the selected frame layout.
-export([callback_arms/2, callback_arms/3]).

-doc "Constructs the checked initializer while preserving source failure references.".
-spec initial_state([hls_source:form()], atom()) -> xls_dslx:value().
initial_state(Forms, StateName) ->
    Clause = xls_init:clause(Forms, hls_gs),
    Init = xls_init:lower(Clause, StateName, fun(R) -> [R, ".1"] end, #{}),
    xls_init:emit("initial_state", xls_names:record_type(StateName), Init).

-doc "Emits request dispatch, ordered callback selection and reply-contract checks for an hls_gs service.".
-spec callback_arms([hls_source:form()], atom()) -> xls_dslx:value().
callback_arms(Forms, StateName) -> callback_arms(Forms, StateName, hls_frame_layout:default()).

-doc "Emits checked callback dispatch under an explicit ordinary-frame capacity.".
-spec callback_arms([hls_source:form()], atom(), hls_frame_layout:layout()) -> xls_dslx:value().
callback_arms(Forms, StateName, Layout) ->
    #{calls := Replies} = hls_service_contract:from_forms(Forms),
    CallGroups = hls_service_contract:groups(Forms, handle_call),
    CastGroups = hls_service_contract:groups(Forms, handle_cast),
    [
        [
            callback_arm({call, maps:get(Tag, Replies)}, Group, StateName, Forms, Layout)
         || Group = {Tag, _} <- CallGroups
        ],
        [callback_arm(cast, Group, StateName, Forms, Layout) || Group <- CastGroups],
        "\n_ => {\n",
        xls_dslx:indent(rejection("ERROR_FUNCTION_CLAUSE"), 2),
        "}\n"
    ].

%% Validate frame length before decoding and selecting this request tag's callback clauses.
-spec callback_arm(
    cast | {call, [atom(), ...]},
    {atom(), [erl_parse:abstract_clause(), ...]},
    atom(),
    [hls_source:form()],
    hls_frame_layout:layout()
) -> xls_dslx:value().
callback_arm(Kind, {Tag, Clauses}, StateName, Forms, Layout) ->
    Arguments = [
        xls_pattern_lower:record_argument(
            Tag,
            "request",
            public_record_value(Tag, "request")
        ),
        xls_pattern_lower:record_argument(
            StateName,
            "state_record.1",
            "state_record"
        )
    ],
    {clause, Line, _, _, _} = hd(Clauses),
    {Postprocessor, BodyFailure} = callbacks(Kind),
    NoClauseFailure = failure(xls_failure_sites:at(function_clause, Line)),
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        StateName,
        Postprocessor,
        NoClauseFailure,
        BodyFailure,
        #{}
    ),
    [
        "\nu8:",
        integer_to_list(
            maps:get(
                Tag,
                maps:from_list([
                    {Name, I}
                 || {I, Name} <-
                        lists:enumerate([error, StateName | hls_actor_source:tags(Forms)])
                ])
            )
        ),
        " => { // ",
        atom_to_list(Tag),
        "\n",
        "  if frame.header.payload_words != u8:",
        integer_to_list(hls_actor_source:message_words(Forms, Tag, Layout)),
        " {\n",
        xls_dslx:indent(rejection("ERROR_REQUEST_LENGTH"), 4),
        "\n",
        "  } else {\n",
        "    let request = ",
        xls_names:record_codec(Tag),
        "_from_bits(frame.payload);\n",
        xls_dslx:indent(Body, 4),
        xls_dslx:indent(Result, 4),
        "  }\n",
        "},\n"
    ].

%% Calls enforce their reply vocabulary; casts carry only the proposed state.
-spec callbacks(cast | {call, [atom(), ...]}) ->
    {fun((xls_dslx:value()) -> xls_dslx:value()), fun((xls_dslx:value()) -> xls_dslx:value())}.
callbacks({call, Replies}) ->
    {
        fun(R) ->
            [
                "if ",
                lists:join(" || ", [
                    [R, ".1.0 == Tag::", xls_names:enum_member(Tag)]
                 || Tag <- Replies
                ]),
                " {\n",
                "  CallbackResult { response: axis::pack(",
                R,
                ".1.0 as u8, hls_bits::frame_payload(",
                R,
                ".1.2)), data: ",
                R,
                ".2.1, error: u32:0 }\n",
                "} else {\n",
                xls_dslx:indent(failure("hls_failure::REPLY_CONTRACT"), 2),
                "\n}"
            ]
        end,
        fun failure/1
    };
callbacks(cast) ->
    {
        fun(R) -> ["CallbackResult { data: ", R, ".1.1, ..zero!<CallbackResult>() }"] end,
        fun failure/1
    }.

%% Failed callbacks preserve committed data and retain their complete source code.
-spec failure(xls_dslx:value()) -> xls_dslx:value().
failure(Code) ->
    rejection(["hls_failure::source_error(", Code, ")"]).

%% Rejections carry a wire status without manufacturing a callback result.
-spec rejection(xls_dslx:value()) -> xls_dslx:value().
rejection(Code) ->
    [
        "CallbackResult { data: state_record.1, error: ",
        Code,
        ", ..zero!<CallbackResult>() }"
    ].

%% A public record value retains its tag and canonical packed payload.
-spec public_record_value(atom(), xls_dslx:value()) -> xls_dslx:value().
public_record_value(Tag, Raw) ->
    [
        "(Tag::",
        xls_names:enum_member(Tag),
        ", ",
        Raw,
        ", bits_from_",
        xls_names:record_codec(Tag),
        "(",
        Raw,
        "))"
    ].
