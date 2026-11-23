%% Geometry-owned storage; shared callbacks use the common named fields.
-record(cell, {
    step = hls_type:zero() :: hls_nums:u32(),
    diffusion_epoch = hls_type:zero() :: hls_nums:u32(),
    phi = hls_type:zero() :: phi_field:field(),
    best_direction = hls_type:zero() :: hls_nums:u32(),
    anyon = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    noise_quiet = hls_type:zero() :: hls_nums:u32(),
    status_valid = hls_type:zero() :: hls_nums:u32()
}).
