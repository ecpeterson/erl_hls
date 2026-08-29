%%%% xls_gs_lower
%%%%
%%%% Groups xls_gs callback clauses by their wire tag and lowers each group to
%%%% one source-ordered selector. The legacy service template remains in
%%%% xls_parse; Erlang callback forms do not leak into that template.

-module(xls_gs_lower).
-moduledoc false.

-export([callback_arms/2]).

-spec callback_arms([erl_parse:abstract_form()], atom()) -> iolist().
callback_arms(Forms, StateName) ->
    DeclaredTags = xls_parse:find_attribute(Forms, xls_tags),
    CallGroups = callback_groups(Forms, handle_call),
    CastGroups = callback_groups(Forms, handle_cast),
    ok = validate_groups(CallGroups, CastGroups, DeclaredTags),
    [
        [callback_arm(call, Group, StateName) || Group <- CallGroups],
        [callback_arm(cast, Group, StateName) || Group <- CastGroups]
    ].

callback_groups(Forms, Function) ->
    Clauses = xls_parse:find_function(Forms, Function, 2),
    xls_callback_lower:group_by(Clauses, fun callback_tag/1).

callback_tag({clause, _Line, [MessagePattern, _DataPattern], _Guards, _Body}) ->
    xls_callback_lower:record_pattern_name(MessagePattern).

validate_groups(CallGroups, CastGroups, DeclaredTags) ->
    CallTags = [Tag || {Tag, _Clauses} <- CallGroups],
    CastTags = [Tag || {Tag, _Clauses} <- CastGroups],
    UsedTags = CallTags ++ CastTags,
    case [Tag || Tag <- UsedTags, not lists:member(Tag, DeclaredTags)] of
        [] -> ok;
        Undeclared -> error({undeclared_xls_gs_callback_tags, Undeclared})
    end,
    case [Tag || Tag <- CallTags, lists:member(Tag, CastTags)] of
        [] -> ok;
        Ambiguous -> error({ambiguous_xls_gs_callback_tags, Ambiguous})
    end.

callback_arm(Kind, {Tag, Clauses}, StateName) ->
    Arguments = [
        xls_callback_lower:record_argument(
            Tag,
            "request",
            public_record_value(Tag, "request")
        ),
        xls_callback_lower:record_argument(
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
        "\nTag::", uppercase(Tag), " => {\n",
        "  let request = ", record_function_name(Tag),
        "_from_bits(frame.payload);\n",
        xls_parse_io:indent(xls_parse:print(Body), 2),
        xls_parse_io:indent(xls_parse:print(Result), 2),
        "},\n"
    ].

callbacks(call, StateName) ->
    {
        fun(R) ->
            ["(axis::pack(", R, ".1.0 as u8, ", R, ".1.2), ", R, ".2)"]
        end,
        failure("ERROR_FUNCTION_CLAUSE", StateName),
        failure("ERROR_MATCH_FAILURE", StateName)
    };
callbacks(cast, StateName) ->
    {
        fun(R) -> ["(zero!<axis::Frame>(), ", R, ".1)"] end,
        failure("ERROR_FUNCTION_CLAUSE", StateName),
        failure("ERROR_MATCH_FAILURE", StateName)
    }.

failure(Code, StateName) ->
    Struct = record_struct_name(StateName),
    [
        "let s = zero!<", Struct, ">();\n",
        "(axis::pack(Tag::ERROR as u8, ", Code, "), ",
        "(Tag::", uppercase(StateName), ", s))"
    ].

public_record_value(Tag, Raw) ->
    [
        "(Tag::", uppercase(Tag), ", ", Raw, ", bits_from_",
        record_function_name(Tag), "(", Raw, "))"
    ].

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_struct_name(Atom) ->
    string:titlecase(record_function_name(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
