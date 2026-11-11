-module(xls_enum_types_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% The same atom can have different codes in different ordinary source unions.
-spec contextual_codes_test() -> ok.
contextual_codes_test() ->
    {Forms, _} = prepare("root(Cell) -> #cell{phase = busy, fault = busy}.", []),
    Root = hls_source:find_function(Forms, root, 1),
    ?assert(lists:member({<<"uN[2]">>, 1}, typed_literals(Root))),
    ?assert(lists:member({<<"uN[2]">>, 2}, typed_literals(Root))),
    Record = hls_records:find(Forms, cell),
    ?assertEqual([{phase, hls_enum:enum([idle, busy, done])},
        {fault, hls_enum:enum([none, actor, busy])}], hls_records:fields(Record)).

%% Head patterns, nested case patterns and guards all use the declared domain.
-spec patterns_and_guards_test() -> ok.
patterns_and_guards_test() ->
    {_Forms, [Helper]} = prepare("root(Cell) -> #cell{phase = choose(Cell#cell.phase)}.", [
        "-spec choose(mode()) -> mode().",
        "choose(idle) -> busy; choose(X) when X =:= busy -> done; choose(X) -> case X of done -> idle; Other -> Other end."
    ]),
    Codes = typed_literals(maps:get(clauses, Helper)),
    [?assert(lists:member({<<"uN[2]">>, Code}, Codes)) || Code <- [0, 1, 2]],
    ok.

%% Literal aliases receive encoding from later field/argument consumers.
-spec bound_literal_test() -> ok.
bound_literal_test() ->
    {Forms, _} = prepare("root(Cell) -> P = busy, F = busy, #cell{phase = P, fault = F}.", []),
    Codes = typed_literals(hls_source:find_function(Forms, root, 1)),
    ?assert(lists:member({<<"uN[2]">>, 1}, Codes)),
    ?assert(lists:member({<<"uN[2]">>, 2}, Codes)).

%% Bit-compatible unions must not silently reinterpret each other's values.
-spec incompatible_domains_test_() -> [term()].
incompatible_domains_test_() ->
    [?_assertException(error, {incompatible_xls_enum, _, _, _}, prepare(Body, []))
        || Body <- ["root(Cell) -> #cell{phase = Cell#cell.fault}.",
            "root(Cell) -> Cell#cell.phase =:= Cell#cell.fault.",
            "root(Cell) -> P = busy, #cell{phase = P, fault = P}."]].

%% Erlang atom ordering is not the numerical order of declaration codes.
-spec ordering_rejected_test() -> ok.
ordering_rejected_test() ->
    ?assertException(error, {unsupported_xls_enum_ordering, _, '<'},
        prepare("root(Cell) -> Cell#cell.phase < busy.", [])).

%% Unlisted atom values fail at the source type boundary.
-spec unlisted_atom_rejected_test() -> ok.
unlisted_atom_rejected_test() ->
    ?assertException(error, {xls_literal_type, _, missing, _, _},
        prepare("root(Cell) -> #cell{phase = missing}.", [])).

%% An unused raw code remains representable by the generated decoder; it is
%% not cast to a DSLX enum which could assert before a wildcard handles it.
-spec raw_decode_test() -> ok.
raw_decode_test() ->
    Type = hls_enum:enum([none, actor, backend]),
    ?assertEqual(<<"bits as uN[2]">>, iolist_to_binary(xls_type:dslx_from_bits(Type, "bits"))).

%% Parse a small ordinary source module through the public helper preparation.
-spec prepare(string(), [string()]) -> {[hls_source:form()], [map()]}.
prepare(Root, Helpers) ->
    Texts = ["-module(enum_fixture).", "-hls_data(cell).", "-hls_tags([]).",
        "-type mode() :: idle | busy | done.", "-type fault() :: none | actor | busy.",
        "-record(cell, {phase = idle :: mode(), fault = none :: fault()}).", Root | Helpers],
    Forms = [begin {ok, Tokens, _} = erl_scan:string(Text),
        {ok, Form} = erl_parse:parse_form(Tokens), Form end || Text <- Texts],
    xls_helpers:prepare(Forms, [{root, 1}]).

%% Inspect encoded constants without relying on generated temporary names.
-spec typed_literals(term()) -> [{binary(), integer()}].
typed_literals({xls_typed_integer, _, Type, Value}) -> [{iolist_to_binary(Type), Value}];
typed_literals(Term) when is_tuple(Term) -> typed_literals(tuple_to_list(Term));
typed_literals(Term) when is_list(Term) -> lists:append([typed_literals(X) || X <- Term]);
typed_literals(_) -> [].

%% Reach the public artifact emitter, including case shape selection and pattern
%% predicates, rather than stopping at the source-preparation passes.
-spec complete_actor_emission_test() -> ok.
complete_actor_emission_test() ->
    Artifact = xls_parse:to_artifact("test/hls_enum_fixture.erl"),
    ?assert(byte_size(xls_emitted:bytes(Artifact)) > 0),
    ?assertEqual(<<1:2, 2:2>>, hls_enum_fixture:pack({response, busy, busy})),
    ?assertEqual({{response, busy, busy}, <<>>},
        hls_enum_fixture:unpack(response, <<1:2, 2:2>>)).

%% A repeated variable is an equality test, including across function arguments
%% and a later case, so it must not compare unrelated raw enum encodings.
-spec repeated_variable_domains_test_() -> [term()].
repeated_variable_domains_test_() ->
    [?_assertException(error, {incompatible_xls_enum, _, _, _}, prepare(Root, Helpers))
        || {Root, Helpers} <- [
            {"root(Cell) -> same(Cell#cell.phase, Cell#cell.fault).", [
                "-spec same(mode(), fault()) -> boolean().",
                "same(X, X) -> true; same(_, _) -> false."]},
            {"root(Cell) -> P = Cell#cell.phase, case Cell#cell.fault of P -> true; _ -> false end.", []}
        ]].

%% Framework callbacks retain their own phase/event tag representation, while
%% ordinary field values below those callback heads may use finite atom unions.
-spec callback_abi_test() -> ok.
callback_abi_test() ->
    ?assert(byte_size(iolist_to_binary(xls_parse:to_xls("test/xls_static_actions_fixture.erl"))) > 0).

%% Structural equality must recurse through enum-bearing fields, rather than
%% comparing equal-width tuple elements as unrelated numerical codes.
-spec structural_domains_test() -> ok.
structural_domains_test() ->
    ?assertException(error, {incompatible_xls_enum, _, _, _},
        prepare("root(Cell) -> {Cell#cell.phase} =:= {Cell#cell.fault}.", [])),
    {Forms, _} = prepare("root(Cell) -> {Cell#cell.phase} =:= {busy}.", []),
    ?assert(lists:member({<<"uN[2]">>, 1},
        typed_literals(hls_source:find_function(Forms, root, 1)))).

%% Being represented by bits does not make Erlang atoms arithmetic operands.
-spec enum_arithmetic_rejected_test_() -> [term()].
enum_arithmetic_rejected_test_() ->
    [?_assertException(error, {unsupported_xls_enum_operator, _, _}, prepare(Body, []))
        || Body <- ["root(Cell) -> Cell#cell.phase bxor Cell#cell.phase.",
            "root(Cell) -> Cell#cell.phase + Cell#cell.phase.",
            "root(Cell) -> bnot Cell#cell.phase.",
            "root(Cell) -> -Cell#cell.phase."]].

%% Boolean truth has its own canonical encoding; an enum's declaration order
%% must not turn true into numerical zero in a condition or Boolean operation.
-spec boolean_union_rejected_test_() -> [term()].
boolean_union_rejected_test_() ->
    [?_assertException(error, {unsupported_hls_boolean_union, _},
        hls_atom_types:descriptor(Type, [])) || Source <- ["true | false", "none | true | false"],
        Type <- [begin {ok, Tokens, _} = erl_scan:string("-type value() :: " ++ Source ++ "."),
            {ok, {attribute, _, type, {value, T, []}}} = erl_parse:parse_form(Tokens), T end]].

%% Container-provider operations have not acquired enum type-flow contracts;
%% reject that source shape instead of silently admitting untyped encoded bits.
-spec collection_domain_rejected_test() -> ok.
collection_domain_rejected_test() ->
    Texts = ["-module(enum_collection).", "-hls_data(cell).", "-hls_tags([]).",
        "-type mode() :: idle | busy.",
        "-record(cell, {items = hls_type:zero() :: hls_vec:vector(mode(), 2)})."],
    Forms = [begin {ok, Tokens, _} = erl_scan:string(T),
        {ok, Form} = erl_parse:parse_form(Tokens), Form end || T <- Texts],
    ?assertException(error, {unsupported_hls_enum_container, _, _, _}, hls_records:resolve(Forms)).

%% A two-member enum's bit representation must not become Boolean truth, nor
%% enter a provider which has no declared atom-domain argument contract.
-spec enum_implicit_coercion_rejected_test() -> ok.
enum_implicit_coercion_rejected_test() ->
    ?assertException(error, {unsupported_xls_enum_guard, _},
        prepare("root(Cell) -> if Cell#cell.phase -> true; true -> false end.", [])),
    ?assertException(error, {unsupported_xls_enum_provider_call, _, _},
        prepare("root(Cell) -> hls_nums:wrap(hls_nums:uN(2), Cell#cell.phase).", [])).
