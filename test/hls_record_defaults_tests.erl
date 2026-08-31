-module(hls_record_defaults_tests).

-include_lib("eunit/include/eunit.hrl").

zero_default_is_accepted_test() ->
    Record = parse_record(
        "-record(example, {value = hls_type:zero() :: hls_nums:u32()})."
    ),
    ?assertEqual(ok, xls_parse:validate_record_defaults(Record)).

missing_default_is_rejected_test() ->
    Record = parse_record(
        "-record(example, {value :: hls_nums:u32()})."
    ),
    ?assertError(
        {missing_hls_record_default, example, value, 1},
        xls_parse:validate_record_defaults(Record)
    ).

explicit_default_is_rejected_test() ->
    Record = parse_record(
        "-record(example, {value = 0 :: hls_nums:u32()})."
    ),
    ?assertError(
        {invalid_hls_record_default, example, value, 1},
        xls_parse:validate_record_defaults(Record)
    ).

parse_record(Source) ->
    {ok, Tokens, _EndLocation} = erl_scan:string(Source),
    {ok, Record} = erl_parse:parse_form(Tokens),
    Record.
