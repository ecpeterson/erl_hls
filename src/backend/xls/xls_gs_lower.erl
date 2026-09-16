%%%% xls_gs_lower
%%%%
%%%% Lowers hls_gs initialization and groups callback clauses by wire tag.
%%%% Erlang forms stay outside the service template in xls_parse.

-module(xls_gs_lower).
-moduledoc false.

-export([initial_state/2, callback_arms/2]).

initial_state(Forms, StateName) ->
    Clause = xls_init:clause(Forms, hls_gs),
    Init = xls_init:lower(Clause, StateName, fun(R) -> [R, ".1"] end, #{}),
    xls_init:emit("initial_state", xls_names:record_type(StateName), Init).

-spec callback_arms([erl_parse:abstract_form()], atom()) -> iolist().
callback_arms(Forms, StateName) ->
    #{calls := Replies} = hls_service_contract:from_forms(Forms),
    CallGroups = hls_service_contract:groups(Forms, handle_call),
    CastGroups = hls_service_contract:groups(Forms, handle_cast),
    [
        [callback_arm({call, maps:get(Tag, Replies)}, Group, StateName, Forms)
            || Group = {Tag, _} <- CallGroups],
        [callback_arm(cast, Group, StateName, Forms) || Group <- CastGroups],
        "\n_ => {\n",
        xls_parse_io:indent(failure("ERROR_FUNCTION_CLAUSE", StateName), 2),
        "}\n"
    ].

callback_arm(Kind, {Tag, Clauses}, StateName, Forms) ->
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
    {Postprocessor, NoClauseFailure, BodyFailure} = callbacks(Kind, StateName),
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
        "\nTag::", xls_names:enum_member(Tag), " => {\n",
        "  if frame.header.payload_words != u8:",
        integer_to_list(xls_parse:message_words(Forms, Tag)), " {\n",
        "    (axis::pack(Tag::ERROR as u8, ERROR_REQUEST_LENGTH), state_record)\n",
        "  } else {\n",
        "    let request = ", xls_names:record_codec(Tag),
        "_from_bits(frame.payload);\n",
        xls_parse_io:indent(xls_parse:print(Body), 4),
        xls_parse_io:indent(xls_parse:print(Result), 4),
        "  }\n",
        "},\n"
    ].

callbacks({call, Replies}, StateName) ->
    {
        fun(R) ->
            ["if ", lists:join(" || ", [
                [R, ".1.0 == Tag::", xls_names:enum_member(Tag)] || Tag <- Replies
            ]), " {\n",
            "  (axis::pack(", R, ".1.0 as u8, hls_bits::frame_payload(", R, ".1.2)), ", R, ".2)\n",
            "} else {\n",
            xls_parse_io:indent(failure("ERROR_REPLY_CONTRACT", StateName), 2),
            "\n}"]
        end,
        failure("ERROR_FUNCTION_CLAUSE", StateName),
        fun(Kind) -> failure(["hls_failure::kind(", Kind, ") as u32"], StateName) end
    };
callbacks(cast, StateName) ->
    {
        fun(R) -> ["(zero!<axis::Frame>(), ", R, ".1)"] end,
        failure("ERROR_FUNCTION_CLAUSE", StateName),
        fun(Kind) -> failure(["hls_failure::kind(", Kind, ") as u32"], StateName) end
    }.

failure(Code, StateName) ->
    Struct = xls_names:record_type(StateName),
    [
        "let s = zero!<", Struct, ">();\n",
        "(axis::pack(Tag::ERROR as u8, ", Code, "), ",
        "(Tag::", xls_names:enum_member(StateName), ", s))"
    ].

public_record_value(Tag, Raw) ->
    [
        "(Tag::", xls_names:enum_member(Tag), ", ", Raw, ", bits_from_",
        xls_names:record_codec(Tag), "(", Raw, "))"
    ].
