%% Small shared schemas for topology routing and startup packing tests.
%% Tags are shared only so direct transports can check selector equality.
-hls_tags([sample, move, delta, config, request, query, reply, report, result, seed, measurement, status]).

%% Sample wire shape used by the routing fixtures.
-record(sample, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    values = hls_type:zero() :: hls_nums:u64()
}).

%% Move wire shape used by the routing fixtures.
-record(move, {
    step = hls_type:zero() :: hls_nums:u32(),
    present = hls_type:zero() :: hls_nums:u32()
}).

%% Delta wire shape used by the routing fixtures.
-record(delta, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:s32()
}).

%% Config wire shape used by the routing fixtures.
-record(config, {
    seed = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

%% Request wire shape used by the routing fixtures.
-record(request, {
    step = hls_type:zero() :: hls_nums:u32()
}).

%% Query wire shape used by the routing fixtures.
-record(query, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32()
}).

%% Reply wire shape used by the routing fixtures.
-record(reply, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32(),
    flags = hls_type:zero() :: hls_nums:u32()
}).

%% Report wire shape used by the routing fixtures.
-record(report, {
    step = hls_type:zero() :: hls_nums:u32(),
    flags = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

%% Result wire shape used by the routing fixtures.
-record(result, {
    step = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    direction = hls_type:zero() :: hls_nums:u32()
}).

%% Seed wire shape used by the routing fixtures.
-record(seed, {
    seed = hls_type:zero() :: hls_nums:u32()
}).

%% Measurement wire shape used by the routing fixtures.
-record(measurement, {
    request_id = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    value = hls_type:zero() :: hls_nums:u32()
}).

%% Status wire shape used by the routing fixtures.
-record(status, {
    step = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    flags = hls_type:zero() :: hls_nums:u32()
}).
