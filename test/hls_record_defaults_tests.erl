-module(hls_record_defaults_tests).

-include_lib("eunit/include/eunit.hrl").

%% The typed zero sentinel is accepted as a hardware record field default.
-spec zero_default_is_accepted_test() -> ok.
zero_default_is_accepted_test() ->
    Record = parse_record(
        "-record(example, {value = hls_type:zero() :: hls_nums:u32()})."
    ),
    ?assertEqual(ok, hls_records:validate_defaults(Record)).

%% A typed field without the required zero sentinel reports its record, field and line.
-spec missing_default_is_rejected_test() -> ok.
missing_default_is_rejected_test() ->
    Record = parse_record(
        "-record(example, {value :: hls_nums:u32()})."
    ),
    ?assertError(
        {missing_hls_record_default, example, value, 1},
        hls_records:validate_defaults(Record)
    ).

%% A literal zero is rejected because hardware defaults require the typed sentinel.
-spec explicit_default_is_rejected_test() -> ok.
explicit_default_is_rejected_test() ->
    Record = parse_record(
        "-record(example, {value = 0 :: hls_nums:u32()})."
    ),
    ?assertError(
        {invalid_hls_record_default, example, value, 1},
        hls_records:validate_defaults(Record)
    ).

parse_record(Source) ->
    {ok, Tokens, _EndLocation} = erl_scan:string(Source),
    {ok, Record} = erl_parse:parse_form(Tokens),
    Record.
