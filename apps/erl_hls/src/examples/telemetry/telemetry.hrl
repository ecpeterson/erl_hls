%% Shared wire records keep the same schema selector and field order at both actors.
%% The ordinary three-word payload holds every record, including the 83-bit summary.
-hls_tags([configure, raw, reading, summary]).

%% Calibration changes affect subsequently selected raw samples.
-record(configure, {
    offset = hls_type:zero() :: hls_nums:s16(),
    gain = hls_type:zero() :: hls_nums:u8()
}).

%% Sequence numbers are caller labels; they need not be contiguous or increasing.
-record(raw, {
    sequence = hls_type:zero() :: hls_nums:u16(),
    value = hls_type:zero() :: hls_nums:s16()
}).

%% A calibrated sample records whether saturation changed its value.
-record(reading, {
    sequence = hls_type:zero() :: hls_nums:u16(),
    value = hls_type:zero() :: hls_nums:s16(),
    clipped = hls_type:zero() :: hls_bool:bool()
}).

%% One nonoverlapping four-sample window, labeled by its final sample.
-record(summary, {
    sequence = hls_type:zero() :: hls_nums:u16(),
    sum = hls_type:zero() :: hls_nums:s32(),
    minimum = hls_type:zero() :: hls_nums:s16(),
    maximum = hls_type:zero() :: hls_nums:s16(),
    clipped = hls_type:zero() :: hls_nums:uN(3)
}).
