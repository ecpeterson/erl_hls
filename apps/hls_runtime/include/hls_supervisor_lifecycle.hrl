-ifndef(HLS_SUPERVISOR_LIFECYCLE_HRL).
-define(HLS_SUPERVISOR_LIFECYCLE_HRL, true).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% One fixed supervisor owns a finite set of independently resettable children.
-type supervisor_phase() :: unbound | starting | running | stopping | stopped | failed.
%% Initial startup and replacement retain different OTP failure meanings.
-type supervisor_child_phase() :: fresh | starting | running | restarting | retiring | retired.
%% The first shutdown cause remains visible after every child has retired.
-type supervisor_reason() :: none | requested | initialization_failure | intensity_exhausted | identities_exhausted | clock_failure | child_state_failure.
%% Start installs one immutable grant; only exact-incarnation stop changes its lifetime.
-type supervisor_operation() :: inspect | start | stop | reject.
%% Rejected control requests do not change incarnation or grant ownership.
-type supervisor_status() :: ok | accepted | replay | stale | invalid.

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

%% An ordered lifecycle observation accompanies the selected zero-based child slot.
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
