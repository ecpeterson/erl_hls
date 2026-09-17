-hls_tags([configure, kick, work, result, report]).
-record(configure, {id = hls_type:zero() :: hls_nums:u32()}).
-record(kick, {round = hls_type:zero() :: hls_nums:u32()}).
-record(work, {sequence = hls_type:zero() :: hls_nums:u32()}).
-record(result, {id = hls_type:zero() :: hls_nums:u32(),
                 sequence = hls_type:zero() :: hls_nums:u32()}).
-record(report, {round = hls_type:zero() :: hls_nums:u32(),
                 sum = hls_type:zero() :: hls_nums:u32()}).
