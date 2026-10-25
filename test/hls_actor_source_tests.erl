-module(hls_actor_source_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Generic queries preserve first-match and declaration-order semantics.
-spec source_queries_test() -> ok.
source_queries_test() ->
    Spec = form("-spec init(term()) -> #data{}."),
    Function = form("init(first) -> first; init(_) -> second."),
    Forms = [{attribute, 1, hls_data, explicit}, Spec, Function,
        {attribute, 5, hls_data, ignored}],
    ?assertEqual(explicit, hls_source:find_attribute(Forms, hls_data)),
    ?assertEqual({ok, explicit}, hls_source:find_optional_attribute(Forms, hls_data)),
    ?assertEqual(none, hls_source:find_optional_attribute(Forms, absent)),
    ?assertEqual(Spec, hls_source:find_spec(Forms, init, 1)),
    {function, _, init, 1, Clauses} = Function,
    ?assertEqual(Clauses, hls_source:find_function(Forms, init, 1)),
    ?assertError({badmatch, false}, hls_source:find_attribute(Forms, absent)),
    ?assertError({badmatch, false}, hls_source:find_spec(Forms, init, 0)),
    ?assertError({badmatch, false}, hls_source:find_function(Forms, missing, 1)).

%% Explicit actor data takes precedence over the legacy initializer return type.
-spec actor_state_declaration_test() -> ok.
actor_state_declaration_test() ->
    Spec = form("-spec init(term()) -> #data{}."),
    ?assertEqual(data, hls_actor_source:state([Spec])),
    ?assertEqual(explicit, hls_actor_source:state(
        [Spec, {attribute, 2, hls_data, explicit}])),
    ?assertError({badmatch, false}, hls_actor_source:state([])).

%% Wire words count provider padding, retain zero-width fields, and round only once.
-spec record_width_matches_host_codec_test() -> ok.
record_width_matches_host_codec_test() ->
    Record = form("-record(message, {flag = hls_type:zero() :: hls_bits:padded(hls_bool:bool(), 8),"
        " count = hls_type:zero() :: hls_nums:uN(25),"
        " empty = hls_type:zero() :: hls_bits:bits(0)})."),
    Fields = hls_records:fields(Record),
    ?assertEqual([flag, count, empty], [Name || {Name, _} <- Fields]),
    ?assertEqual(ok, hls_records:validate_defaults(Record)),
    ?assertEqual(33, hls_records:width(Record)),
    ?assertEqual(33, bit_size(hls_record:pack({message, true, 42, <<>>}, message, Fields))),
    ?assertEqual(2, hls_actor_source:message_words([Record], message)),
    ?assertEqual(Record, hls_records:find([Record], message)).

%% The source-level transport limit remains independent of record rendering.
-spec message_width_limit_test() -> ok.
message_width_limit_test() ->
    Empty = form("-record(empty, {})."),
    Full = form("-record(full, {bits = hls_type:zero() :: hls_bits:bits(96)})."),
    Wide = form("-record(wide, {bits = hls_type:zero() :: hls_bits:bits(97)})."),
    ?assertEqual(0, hls_actor_source:message_words([Empty], empty)),
    ?assertEqual(3, hls_actor_source:message_words([Full], full)),
    ?assertError({xls_message_too_wide, wide, 97, 96},
        hls_actor_source:message_words([Wide], wide)).

%% Querying typed fields is distinct from admitting an actor's complete record declaration.
-spec untyped_record_field_test() -> ok.
untyped_record_field_test() ->
    Record = {attribute, _, record, {mixed, [Untyped, _]}} = form(
        "-record(mixed, {host_only, value = hls_type:zero() :: hls_nums:u8()})."),
    ?assertEqual([{value, hls_nums:u8()}], hls_records:fields(Record)),
    ?assertEqual(8, hls_records:width(Record)),
    ?assertError({untyped_xls_record_field, mixed, Untyped}, hls_records:validate_defaults(Record)).

%% Parse isolated declarations without loading source modules or running transforms.
-spec form(string()) -> erl_parse:abstract_form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
