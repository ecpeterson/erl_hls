-module(xls_struct_codec_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Layouts retain declared order while the encoding determines how prefixes are interpreted.
-spec typed_layout_policies_test() -> ok.
typed_layout_policies_test() ->
    Flag = hls_bool:bool(),
    Padded = hls_bits:padded(hls_nums:sN(3), 7),
    Empty = hls_bits:bits(0),
    Count = hls_nums:uN(9),
    Fields = [{flag, Flag}, {padded, Padded}, {empty, Empty}, {count, Count}],
    Expected = [#{name => flag, type => Flag, prefix => 0, width => 1},
        #{name => padded, type => Padded, prefix => 1, width => 7},
        #{name => empty, type => Empty, prefix => 8, width => 0},
        #{name => count, type => Count, prefix => 8, width => 9}],
    lists:foreach(fun(Encoding) ->
        ?assertEqual(#{encoding => Encoding, width => 17, fields => Expected},
            hls_field_layout:layout(Fields, Encoding))
    end, [stream, lsb]),
    ok.

%% Empty structures and zero-width fields are distinct layouts with the same total width.
-spec zero_width_layout_test() -> ok.
zero_width_layout_test() ->
    lists:foreach(fun(Encoding) ->
        ?assertEqual(#{encoding => Encoding, width => 0, fields => []},
            hls_field_layout:layout([], Encoding)),
        Type = hls_bits:bits(0),
        ?assertEqual(#{encoding => Encoding, width => 0,
            fields => [#{name => empty, type => Type, prefix => 0, width => 0}]},
            hls_field_layout:layout([{empty, Type}], Encoding))
    end, [stream, lsb]),
    ok.
