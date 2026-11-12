-ifndef(HLS_SUPERVISOR_LIFECYCLE_HRL).
-define(HLS_SUPERVISOR_LIFECYCLE_HRL, true).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% One fixed supervisor owns a finite set of independently resettable children.
-type supervisor_phase() :: unbound | starting | running | stopping | stopped | failed.
%% Initial startup and replacement retain different OTP failure meanings.
-type supervisor_child_phase() :: fresh | starting | running | restarting | retiring | retired | vacant | admitting.
%% The first shutdown cause remains visible after every child has retired.
-type supervisor_reason() :: none | requested | initialization_failure | intensity_exhausted | identities_exhausted | clock_failure | child_state_failure.
%% A temporary occupant is never restarted; its compiled slot survives retirement.
-type supervisor_policy() :: permanent | temporary.
%% Parent and selected-child commands always name the lifetime they may change.
-type supervisor_operation() :: inspect | start | stop | reject | start_child | stop_child.
%% Rejected control requests do not change incarnation or grant ownership.
-type supervisor_status() :: ok | accepted | replay | stale | invalid | busy | exhausted.

%% Per-child bookkeeping is stored alongside, but outside, its resettable domain.
-record(supervisor_child, {
    phase = fresh :: supervisor_child_phase(),
    expected = 0 :: hls_nums:u64(),
    target = 0 :: hls_nums:u64()
}).

%% At most sixteen recent restart timestamps implement the configured sliding window.
-record(supervisor_state, {
    phase = unbound :: supervisor_phase(),
    epoch = 0 :: hls_nums:u64(),
    first = 0 :: hls_nums:u64(),
    last = 0 :: hls_nums:u64(),
    next = 0 :: hls_nums:u64(),
    children = 0 :: hls_nums:u16(),
    started = 0 :: hls_nums:u16(),
    retired = 0 :: hls_nums:u16(),
    intensity = 0 :: hls_nums:u8(),
    period = 0 :: hls_nums:u32(),
    last_time = 0 :: hls_nums:u64(),
    reason = none :: supervisor_reason(),
    head = 0 :: hls_nums:u8(),
    count = 0 :: hls_nums:u8(),
    times = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] :: hls_vec:vector(hls_nums:u64(), 16)
}).

%% Policy/dormant are immutable slot metadata. Reusable certifies transport retirement,
%% including old output/watch state; it is not inferred from an elapsed timeout.
%% Expected_child names the current occupant or retained vacant-slot tombstone.
-record(supervisor_input, {
    op = inspect :: supervisor_operation(),
    epoch = 0 :: hls_nums:u64(),
    first = 0 :: hls_nums:u64(),
    last = 0 :: hls_nums:u64(),
    children = 0 :: hls_nums:u16(),
    intensity = 0 :: hls_nums:u8(),
    period = 0 :: hls_nums:u32(),
    now = 0 :: hls_nums:u64(),
    slot = 0 :: hls_nums:u16(),
    policy = permanent :: supervisor_policy(),
    dormant = false :: boolean(),
    reusable = false :: boolean(),
    expected_child = 0 :: hls_nums:u64(),
    child = #supervisor_child{} :: #supervisor_child{},
    observed = #domain_state{} :: #domain_state{}
}).

%% The composer commits both state values and issues at most one ordered child command.
-record(supervisor_output, {
    status = ok :: supervisor_status(),
    state = #supervisor_state{} :: #supervisor_state{},
    child = #supervisor_child{} :: #supervisor_child{},
    command_valid = false :: boolean(),
    command = #domain_input{} :: #domain_input{}
}).
-endif.
