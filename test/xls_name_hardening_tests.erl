-module(xls_name_hardening_tests).
-moduledoc "Regressions for provider aliases, deployment keywords and local/type shadowing.".
-include_lib("eunit/include/eunit.hrl").
-include("../src/backend/xls/xls_parse.hrl").
-export([dslx_imports/0]).

-doc "Supplies provider import declarations chosen by each test.".
-spec dslx_imports() -> [atom()].
dslx_imports() -> get(name_test_imports).

%% A legal source record used to become the same identifier as a value binding.
-spec record_shadow_test() -> ok.
record_shadow_test() ->
    ?assertEqual("Value_1", xls_names:record_type('_Value_1')),
    {Name, State} = xls_parse:uniquify(#clause_state{}, 'Value'),
    ?assertEqual("v_Value_1", Name),
    ?assertEqual("v_Value_2", element(1, xls_parse:uniquify(State, 'Value'))),
    ?assertEqual("v__Value_1", element(1, xls_parse:uniquify(State, '_Value'))).

%% Import paths can differ while declaring the same local module alias.
-spec import_aliases_test() -> ok.
import_aliases_test() ->
    ?assertError({xls_import_alias_collision, "fixed", 'math.fixed', 'other.fixed'},
        xls_dslx_imports:emit(['math.fixed'], ['other.fixed'])),
    ?assertEqual(<<"import math.fixed;\n">>,
        iolist_to_binary(xls_dslx_imports:emit(['math.fixed'], ['math.fixed']))),
    ?assertError({reserved_dslx_import_alias, v_Value_1, "v_Value_1"},
        xls_dslx_imports:emit([], [v_Value_1])),
    lists:foreach(fun(Module) ->
        Alias = atom_to_list(Module),
        ?assertError({reserved_dslx_import_alias, Module, Alias},
            xls_dslx_imports:emit([], [Module]))
    end, ['_0', hls_local_helper__1, 'XLS_FAILURE_SITE_1']).

%% Provider aliases share a scope with actor types; diagnose both declarations.
-spec import_declaration_collision_test() -> ok.
import_declaration_collision_test() ->
    put(name_test_imports, ['some.Data']),
    try
        ?assertException(error, {xls_name_collision, module, "Data",
            #{kind := import, name := 'some.Data'}, #{kind := record_type, name := data}},
            xls_names:actor(forms(), hls_gs))
    after erase(name_test_imports) end.

%% All identifier consumers use the pinned scanner's sized and plain keywords.
-spec deployment_keywords_test() -> ok.
deployment_keywords_test() ->
    lists:foreach(fun(Name) ->
        Text = atom_to_list(Name),
        ?assertError({reserved_dslx_identifier, topology_name, Text},
            xls_topology_profile:identifier(Name, topology_name))
    end, [bool, u32, s64, true, false, chan, token]),
    ?assertEqual("out", xls_topology_profile:identifier(out, {actor_output, example})),
    ?assertEqual("bool", xls_topology_profile:identifier(bool, external_id)),
    ?assertError({reserved_dslx_identifier, family_module, "axis"},
        xls_topology_profile:identifier(axis, family_module)),
    ?assertEqual("u65", xls_topology_profile:identifier(u65, topology_name)).

%% An unused provider call is enough to declare its companion module.
-spec forms() -> [hls_source:form()].
forms() -> [form(S) || S <- ["-module(name_fixture).", "-hls_data(data).",
    "-hls_tags([request]).", "-record(data, {x :: hls_nums:u8()}).",
    "-record(request, {x :: hls_nums:u8()}).",
    "provider() -> xls_name_hardening_tests:unused()."]].

%% Parse one declaration without needing a temporary file.
-spec form(string()) -> erl_parse:abstract_form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens), Form.
