-module(xls_type_tests).
-moduledoc "Compiler-provider dispatch witnesses. Built-ins retain runtime descriptors and host-only imports; custom callbacks compose through the same DSLX boundary without registration.".
-include_lib("eunit/include/eunit.hrl").
-include("../src/backend/xls/xls_clause_lower.hrl").
-behaviour(xls_type).

%% A custom compiler provider used to witness extension dispatch.
-export([width/2, print_type/2, transpile/3, dslx_codec/2, dslx_imports/0, dslx_imports/1]).

%% Runtime provider BEAMs must not import compiler implementation modules.
-spec runtime_providers_have_no_compiler_imports_test() -> ok.
runtime_providers_have_no_compiler_imports_test() ->
    lists:foreach(fun(Module) ->
        {ok, {Module, [{imports, Imports}]}} = beam_lib:chunks(code:which(Module), [imports]),
        ?assertEqual({Module, []}, {Module, [M || {M, _, _} <- Imports,
            lists:prefix("xls_", atom_to_list(M))]}),
        ?assertEqual([], [Name || {Name, _} <- Module:module_info(exports),
            lists:member(Name, [transpile, print_type, dslx_codec, dslx_imports,
                dslx_from_bits, dslx_to_bits])])
    end, [hls_type, hls_bits, hls_bool, hls_fixed, hls_float, hls_gs,
          hls_lists, hls_nums, hls_prng, hls_record, hls_serial, hls_vec]).

%% Type construction during lowering retains the runtime provider's identity.
-spec builtin_descriptors_and_operations_test() -> ok.
builtin_descriptors_and_operations_test() ->
    State = #clause_state{},
    Numeric = xls_type:transpile(hls_nums, uN, [{static, integer, 13}], State),
    ?assertEqual({phantom, type, hls_nums:uN(13)}, xls_clause_lower:reference(Numeric)),
    Fixed = xls_type:transpile(hls_fixed, signed,
        [{static, integer, 16}, {static, integer, 8}], State),
    ?assertEqual({phantom, type, hls_fixed:signed(16, 8)}, xls_clause_lower:reference(Fixed)),
    Wrapped = xls_type:transpile(hls_nums, wrap,
        [{phantom, type, hls_nums:u8()}, {static, integer, -1}], State),
    ?assertEqual(<<"u8:255">>, rendered(Wrapped)),
    ?assertMatch({fallible, badarg, _}, xls_type:transpile(hls_serial, difference,
        [{phantom, type, hls_serial:counter(8)}, "a", "b"], State)),
    ?assertEqual(<<"u64">>, rendered(xls_type:print_type(hls_gs:from()))).

%% A custom provider remains its own callback owner; nested built-ins compose it.
-spec custom_callbacks_compose_without_registration_test() -> ok.
custom_callbacks_compose_without_registration_test() ->
    Custom = {hls_type, ?MODULE, value, []},
    ?assertEqual(?MODULE, xls_type:provider(?MODULE)),
    ?assertEqual(<<"custom::Value">>, rendered(xls_type:print_type(Custom))),
    Call = xls_type:transpile(?MODULE, emit, ["x"], #clause_state{}),
    ?assertEqual(<<"custom::emit(x)">>, rendered(Call)),
    Nested = hls_vec:vector(hls_bits:padded(Custom, 16), 2),
    ?assertEqual(<<"custom::Value[2]">>, rendered(xls_type:print_type(Nested))),
    ?assertNotEqual(nomatch, binary:match(rendered(xls_type:dslx_from_bits(Nested, "raw")),
        <<"custom::decode(">>)),
    ?assertNotEqual(nomatch, binary:match(rendered(xls_type:dslx_to_bits(Nested, "value")),
        <<"custom::encode(">>)).

%% Named imports take precedence and preserve custom ownership alongside built-ins.
-spec custom_and_builtin_imports_share_resolution_test() -> ok.
custom_and_builtin_imports_share_resolution_test() ->
    {ok, Tokens, _} = erl_scan:string(
        "probe() -> xls_type_tests:emit(hls_vec:nth(1, [a]))."),
    {ok, Form} = erl_parse:parse_form(Tokens),
    ?assertEqual([custom_ops, hls_bits, hls_lists], xls_dslx_imports:from_forms([Form])).

-doc "Supplies the custom field's physical width for nested compiler layouts.".
-spec width(value, []) -> 8.
width(value, []) -> 8.

-doc "Names a custom DSLX value type.".
-spec print_type(value, []) -> string().
print_type(value, []) -> "custom::Value".

-doc "Emits one custom source operation through a structured target call.".
-spec transpile(emit, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> xls_dslx:expr().
transpile(emit, [Value], _State) -> xls_dslx:call("custom::emit", [Value]).

-doc "Supplies custom conversion functions used recursively by built-in collections.".
-spec dslx_codec(value, []) -> xls_type:codec().
dslx_codec(value, []) ->
    {fun(Bits) -> xls_dslx:call("custom::decode", [Bits]) end,
     fun(Value) -> xls_dslx:call("custom::encode", [Value]) end}.

-doc "Fails if import resolution bypasses the more specific named callback.".
-spec dslx_imports() -> no_return().
dslx_imports() -> error(named_import_callback_required).

-doc "Declares the custom operation dependency for the selected source use.".
-spec dslx_imports([emit]) -> [custom_ops].
dslx_imports([emit]) -> [custom_ops].

%% Render only after composing every nested compiler fragment.
-spec rendered(xls_dslx:value()) -> binary().
rendered(Value) -> iolist_to_binary(xls_dslx:render(Value)).
