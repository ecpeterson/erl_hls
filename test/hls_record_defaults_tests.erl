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

%% The validator accepts normalized fields, not unprocessed source declarations.
-spec explicit_default_is_rejected_test() -> ok.
explicit_default_is_rejected_test() ->
    Record = parse_record(
        "-record(example, {value = 0 :: hls_nums:u32()})."
    ),
    ?assertError(
        {invalid_hls_record_default, example, value, 1},
        hls_records:validate_defaults(Record)
    ).

%% Native literals and nested records share the provider zero without executing code.
-spec literal_and_nested_typed_zero_defaults_are_normalized_test() -> ok.
literal_and_nested_typed_zero_defaults_are_normalized_test() ->
    Header = [parse_record("-hls_data(cell)."), parse_record("-hls_tags([request]).")],
    Forms = Header ++ [
        parse_record("-record(inner, {count = 0 :: hls_nums:u64(), valid = false :: boolean()})."),
        parse_record("-record(cell, {inner = #inner{} :: #inner{}})."),
        parse_record("-record(request, {value = 0 :: hls_nums:u32()}).")],
    Resolved = hls_records:resolve(Forms),
    lists:foreach(fun(Name) ->
        ?assertEqual(ok, hls_records:validate_defaults(hls_records:find(Resolved, Name)))
    end, [inner, cell, request]),
    ?assertEqual([{count, {hls_type, hls_nums, u64, []}},
        {valid, {hls_type, hls_bool, bool, []}}],
        hls_records:fields(hls_records:find(Resolved, inner))).

%% Zero normalization must not broaden defaults to executable or nonzero expressions.
-spec nonzero_and_executable_defaults_remain_rejected_test() -> ok.
nonzero_and_executable_defaults_remain_rejected_test() ->
    Header = [parse_record("-hls_data(cell)."), parse_record("-hls_tags([]).")],
    lists:foreach(fun(Default) ->
        Forms = Header ++ [parse_record("-record(cell, {value = " ++ Default ++ " :: hls_nums:u32()}).")],
        Resolved = hls_records:resolve(Forms),
        ?assertException(error, {invalid_hls_record_default, cell, value, _},
            hls_records:validate_defaults(hls_records:find(Resolved, cell)))
    end, ["1", "erlang:phash2(self())"]),
    Nested = Header ++ [
        parse_record("-record(inner, {count = 0 :: hls_nums:u32()})."),
        parse_record("-record(cell, {value = #inner{count = 1} :: #inner{}}).")],
    ?assertException(error, {invalid_hls_record_default, cell, value, _},
        hls_records:validate_defaults(hls_records:find(hls_records:resolve(Nested), cell))).

parse_record(Source) ->
    {ok, Tokens, _EndLocation} = erl_scan:string(Source),
    {ok, Record} = erl_parse:parse_form(Tokens),
    Record.
