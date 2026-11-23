-ifndef(HLS_RECOVERY_PROFILE_HRL).
-define(HLS_RECOVERY_PROFILE_HRL, true).

%% One pending/current request, with explicit rejection and unknown observation states.
-define(PROFILE_UNKNOWN, 0).
-define(PROFILE_PENDING, 1).
-define(PROFILE_APPLIED, 2).
-define(PROFILE_STALE, 3).
-define(PROFILE_BUSY, 4).
-define(PROFILE_INVALID, 5).
-define(PROFILE_EXHAUSTED, 6).

%% Incarnation identity belongs to the enclosing domain endpoint; this epoch is configuration-local.
-record(select_profile, {
    request = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32(),
    profile = hls_type:zero() :: hls_nums:u8()
}).
%% Observe only the retained request at its expected epoch, even when IDs are reused.
-record(query_profile, {
    request = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32()
}).
%% Correlate the admitted request and its expected epoch; reused IDs cannot revive an old trigger.
-record(apply_profile, {
    request = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32()
}).
%% Inject a terminal source fault into the finite witness controller.
-record(controller_failure, {reason = hls_type:zero() :: hls_nums:u8()}).

%% UNKNOWN leaves the physical outcome unspecified, including after controller replacement.
-record(profile_status, {
    status = hls_type:zero() :: hls_nums:u8(),
    request = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32(),
    profile = hls_type:zero() :: hls_nums:u8(),
    enabled = hls_type:zero() :: hls_nums:u8()
}).

%% A delivered actuator effect is distinct from whether a later logical result remains usable.
-record(profile_applied, {
    request = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32(),
    profile = hls_type:zero() :: hls_nums:u8(),
    enabled = hls_type:zero() :: hls_nums:u8()
}).

-endif.
