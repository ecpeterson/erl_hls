-module(xls_names_tests).
-include_lib("eunit/include/eunit.hrl").

record_collisions_test_() ->
    [?_assertMatch({xls_name_collision, module, Symbol, _, _},
        reason(fun() -> xls_names:actor(forms(Names), hls_statem) end))
        || {Names, Symbol} <- [
            {[foo_bar, foobar], "Foobar"},
            {[foo, 'Foo'], "Foo"},
            {[a_b, a_B], "ab_from_bits"},
            {[bits], "bits_from_bits"},
            {[tag], "Tag"},
            {['SharedMachine'], "SharedMachine"},
            {['N'], "N"}
        ]].

enum_scopes_test() ->
    Base = forms([value]),
    lists:foreach(fun({Attribute, Scope}) ->
        ?assertMatch({xls_name_collision, Scope, "FOO", _, _}, reason(fun() ->
            xls_names:actor(replace(Base, Attribute, [foo, 'Foo']), hls_statem)
        end))
    end, [{hls_phases, phase}, {hls_outputs, output}]),
    %% Same spelling in independent enums and record fields is harmless.
    ok = xls_names:actor(replace(replace(Base, hls_phases, [value]),
        hls_outputs, [value]), hls_statem).

output_channel_collisions_test_() ->
    [?_assertMatch({xls_name_collision, {proc, 'Top'}, _,
            #{kind := generated}, #{kind := output, name := Name}}, reason(fun() ->
        xls_names:actor(replace(forms([value]), hls_outputs, [Name]), hls_statem)
    end)) || Name <- [req, admit, egress]].

reserved_wire_tags_test_() ->
    [?_assertMatch({xls_name_collision, wire_tag, Name, _, _},
        reason(fun() -> xls_names:wire_tags(forms([Name])) end))
        || Name <- [none, error, data]].

packing_checks_wire_identity_without_dslx_restrictions_test() ->
    ?assertMatch({xls_name_collision, wire_tag, data, _, _}, reason(fun() ->
        hls_pack:parse_transform(forms([data]) ++ [{eof, 30}], [])
    end)),
    Packed = hls_pack:parse_transform(forms([foo_bar, foobar]) ++ [{eof, 30}], []),
    {ok, names, Beam, _Warnings} = compile:forms(Packed, [binary, return_errors, return_warnings]),
    {module, names} = code:load_binary(names, "names.erl", Beam),
    try
        ?assertEqual(3, names:pack_tag(foo_bar)),
        ?assertEqual(4, names:pack_tag(foobar)),
        ?assertEqual(foo_bar, names:unpack_tag(3)),
        ?assertEqual(foobar, names:unpack_tag(4))
    after code:purge(names), code:delete(names) end.

reserved_spelling_test() ->
    ?assertMatch({xls_name_collision, tag, "NONE", _, _}, reason(fun() ->
        xls_names:actor(forms(['None']), hls_statem)
    end)),
    [begin
        ?assertError({reserved_hls_statem_phase, Name},
            xls_names:actor(replace(forms([value]), hls_phases, [Name]), hls_statem))
    end || Name <- [consume, postpone, fail, true, false, repeat_phase, reduce, terminate]],
    ?assertMatch({xls_name_collision, module, "INITIAL_MACHINE", _, _}, reason(fun() ->
        xls_names:actor(forms(['_INITIAL_MACHINE']), hls_statem)
    end)).

identifiers_test_() ->
    [?_assertMatch({invalid_xls_identifier, {field, value}, _,
            #{file := "fields.hrl", line := 23, name := {value, Name}}},
        reason(fun() -> xls_names:actor(field_forms(Name), hls_statem) end))
        || Name <- ['bad-name', 'two words', 'λ', '_', 'fn', 'type', 'match', u32, s64, 'Self']].

valid_identifiers_test_() ->
    [?_assertEqual(ok, xls_names:actor(field_forms(Name), hls_statem))
        || Name <- ['Value', value, '_value', u0, u65, u032, self_field]].

case_conversion_does_not_hide_unsupported_source_spelling_test() ->
    [begin
        ?assertMatch({invalid_xls_identifier, Scope, "ß", _}, reason(fun() ->
            xls_names:actor(replace(forms([value]), Attribute, ['ß']), hls_statem)
        end))
    end || {Attribute, Scope} <- [{hls_phases, phase}, {hls_outputs, output}]],
    ?assertMatch({invalid_xls_identifier, tag, "ß", _}, reason(fun() ->
        xls_names:actor(forms(['ß']), hls_statem)
    end)).

encoding_boundaries_test() ->
    Base = forms([value]),
    [begin
        Values = numbered(Kind, Limit),
        Overflow = Limit + 1,
        ok = xls_names:actor(replace(Base, Attribute, Values), hls_statem),
        ?assertError({xls_namespace_exhausted, Kind, Overflow, Limit},
            xls_names:actor(replace(Base, Attribute, Values ++ [extra]), hls_statem))
    end || {Attribute, Kind, Limit} <- [{hls_phases, phase, 256}, {hls_outputs, output, 255}]],
    ok = xls_names:actor(forms(numbered(message, 253)), hls_statem),
    ?assertError({too_many_hls_tags, 254, 253},
        xls_names:actor(forms(numbered(message, 254)), hls_statem)).

reduction_namespace_test() ->
    Base = forms([value]) ++ [record(fold)],
    Opens = [#{name => sum, line => 31}, #{name => 'SUM', line => 32}],
    ?assertMatch({xls_name_collision, reduction, "SUM", _, _}, reason(fun() ->
        xls_names:reduction(Base, fold, Opens)
    end)),
    ok = xls_names:reduction(Base, fold, [#{name => sum, line => 31}, #{name => sum, line => 32}]),
    ?assertMatch({xls_name_collision, module, "Value", _, _}, reason(fun() ->
        xls_names:reduction(Base ++ [record('Value')], 'Value', [])
    end)),
    ?assertMatch({xls_name_collision, tag, "ERROR", _, _}, reason(fun() ->
        xls_names:reduction(Base ++ [record('Error')], 'Error', [])
    end)),
    ok = xls_names:reduction(forms(numbered(message, 252)) ++ [record(fold)], fold, []),
    ?assertError({too_many_hls_tags_for_reduction, 253, 252},
        xls_names:reduction(forms(numbered(message, 253)) ++ [record(fold)], fold, [])),
    ?assertError({xls_namespace_exhausted, reduction, 257, 256},
        xls_names:reduction(Base, fold, [#{name => N, line => 31} || N <- numbered(reducer, 257)])).

include_origins_test() ->
    Forms = forms([foo_bar, foobar]),
    Located = lists:flatmap(fun
        (F = {attribute, _, record, {foo_bar, _}}) ->
            [{attribute, 1, file, {"first.hrl", 1}}, F];
        (F = {attribute, _, record, {foobar, _}}) ->
            [{attribute, 1, file, {"second.hrl", 1}}, F];
        (F) -> [F]
    end, Forms),
    ?assertMatch({xls_name_collision, module, "Foobar",
        #{name := foo_bar, file := "first.hrl", line := 17},
        #{name := foobar, file := "second.hrl", line := 17}},
        reason(fun() -> xls_names:actor(Located, hls_statem) end)).

translation_and_interface_validate_before_callbacks_test() ->
    %% Invalid declarations alone suffice: no callback/helper lowering runs.
    Forms = forms([foo_bar, foobar]),
    ?assertMatch({xls_name_collision, module, "Foobar", _, _}, reason(fun() ->
        xls_statem_lower:lower("names.erl", Forms, [waiting])
    end)),
    ?assertMatch({xls_name_collision, module, "Foobar", _, _}, reason(fun() ->
        xls_statem_lower:interface(Forms, [waiting])
    end)),
    ?assertMatch({xls_name_collision, module, "Foobar", _, _}, reason(fun() ->
        xls_parse:to_xls_gs("names.erl", Forms)
    end)).

runtime_declarations_remain_reserved_test() ->
    %% Audit the actual emitted surfaces so adding a runtime type/constant
    %% cannot silently reopen a record-name collision. This is a test of the
    %% namespace contract; production validation never scans generated text.
    [begin
        {ok, Forms} = xls_parse:parse_file(Path),
        RecordTypes = [xls_names:record_type(N) || {attribute, _, record, {N, _}} <- Forms],
        Text = iolist_to_binary(xls_parse:to_xls(Path, Options)),
        {match, Declarations} = re:run(Text,
            "^(?:pub )?(?:struct|enum|type|proc|const) ([A-Z][A-Za-z0-9_]*)\\b",
            [multiline, global, {capture, [1], list}]),
        {match, Parameters} = re:run(Text, "\\b([A-Z][A-Z_0-9]*): u32\\b",
            [global, {capture, [1], list}]),
        Matches = lists:usort(Declarations ++ Parameters),
        [begin
            RecordName = list_to_atom("_" ++ Name),
            Result = reason(fun() -> xls_names:actor(forms([RecordName]), Kind) end),
            ?assertMatch({Name, {xls_name_collision, module, Name, _, _}}, {Name, Result})
        end || [Name] <- Matches, not lists:member(Name, RecordTypes)]
    end || {Path, Kind, Options} <- [
        {"src/examples/regsvc/regsvc.erl", hls_gs, #{}},
        {"src/examples/phi_decoder/phenom_data_cell.erl", hls_statem, #{mailbox_debug => true}},
        {"src/examples/phi_decoder/phi_halo_cell.erl", hls_statem, #{shared_service => aggregate_only}}
    ]].

forms(Tags) ->
    [{attribute, 1, file, {"names.erl", 1}}, {attribute, 2, module, names},
        {attribute, 3, hls_data, data}, {attribute, 4, hls_tags, Tags},
        {attribute, 5, hls_phases, [waiting]}, {attribute, 6, hls_outputs, [out]},
        {attribute, 7, hls_mailbox_capacity, 2}, record(data)] ++ [record(T) || T <- Tags].

record(Name) -> {attribute, 17, record, {Name, []}}.

field_forms(Name) ->
    (forms([value]) -- [record(value)]) ++ [{attribute, 1, file, {"fields.hrl", 1}},
        {attribute, 22, record, {value, [{record_field, 23, {atom, 23, Name}}]}}].

replace(Forms, Name, Value) -> [case F of
    {attribute, L, Name, _} -> {attribute, L, Name, Value}; _ -> F
end || F <- Forms].

numbered(Prefix, Count) -> [list_to_atom(atom_to_list(Prefix) ++ integer_to_list(N))
    || N <- lists:seq(1, Count)].

reason(Fun) -> try Fun() catch error:Reason -> Reason end.
