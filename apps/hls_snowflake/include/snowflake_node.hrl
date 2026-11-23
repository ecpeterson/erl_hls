%% Bounded state of one phenomenological Snowflake vertex. Directions are
%% center=0, west=1, east=2, down=3, up=4, north=5, south=6; cid=-1 requests full unrooting.
-record(node, {
    active = hls_type:zero() :: hls_bool:bool(),
    whole = hls_type:zero() :: hls_bool:bool(),
    cid = hls_type:zero() :: hls_nums:s32(),
    defect = hls_type:zero() :: hls_bool:bool(),
    pointer = hls_type:zero() :: hls_nums:u8(),
    grown = hls_type:zero() :: hls_bool:bool(),
    unrooted = hls_type:zero() :: hls_bool:bool(),
    busy = hls_type:zero() :: hls_bool:bool()
}).
