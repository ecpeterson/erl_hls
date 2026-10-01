-module(hls_variable_width_pack_fixture).

-compile({parse_transform, hls_pack}).

-hls_data(state).
-hls_tags([message]).

-record(message, {
    head = hls_type:zero() :: hls_nums:uN(24),
    values = hls_type:zero() :: hls_lists:list(hls_nums:uN(24), 2),
    byte = hls_type:zero() :: hls_nums:u8(),
    tail = hls_type:zero() :: hls_nums:uN(40)
}).

-record(state, {
    value = hls_type:zero() :: hls_nums:uN(24)
}).
