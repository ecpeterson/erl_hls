%% A six-member completion set; identities remain absolute on the incoming side.
-record(barrier, {
    source = hls_type:zero() :: hls_nums:u8(),
    first = hls_type:zero() :: hls_nums:u8(),
    count = hls_type:zero() :: hls_nums:u8(),
    members = hls_type:zero() :: hls_nums:uN(?SNOWFLAKE_BARRIER_SOURCES),
    received = hls_type:zero() :: hls_nums:u8(),
    seen = hls_type:zero() :: hls_nums:uN(6),
    epoch = hls_type:zero() :: hls_nums:u32(),
    kind = hls_type:zero() :: hls_nums:u8(),
    busy = hls_type:zero() :: hls_bool:bool()
}).
