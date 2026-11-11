-ifndef(HLS_DOMAIN_LIFECYCLE_HRL).
-define(HLS_DOMAIN_LIFECYCLE_HRL, true).

%% Lifecycle phases; only READY admits application traffic.
-define(HLS_DOMAIN_UNBOUND, 0).
-define(HLS_DOMAIN_READY, 1).
-define(HLS_DOMAIN_CLOSING, 2).
-define(HLS_DOMAIN_ISOLATED, 3).
-define(HLS_DOMAIN_INITIALIZING, 4).
-define(HLS_DOMAIN_FAILED, 5).

%% Commands and completion indications on the serialized management input.
-define(HLS_DOMAIN_INSPECT, 0).
-define(HLS_DOMAIN_ACTIVATE, 1).
-define(HLS_DOMAIN_REPLACE, 2).
-define(HLS_DOMAIN_FAULT, 3).
-define(HLS_DOMAIN_FENCED, 4).
-define(HLS_DOMAIN_RESET_DONE, 5).
-define(HLS_DOMAIN_INITIALIZED, 6).
-define(HLS_DOMAIN_ABORT, 7).

%% Responses describe admission of the management input, not physical completion.
-define(HLS_DOMAIN_OK, 0).
-define(HLS_DOMAIN_ACCEPTED, 1).
-define(HLS_DOMAIN_REPLAY, 2).
-define(HLS_DOMAIN_STALE, 3).
-define(HLS_DOMAIN_BUSY, 4).
-define(HLS_DOMAIN_INVALID, 5).
-define(HLS_DOMAIN_FAILURE, 6).
-define(HLS_DOMAIN_COMPLETED, 7).

%% Phase-level work requests; PUBLISH is emitted only on readiness completion.
-define(HLS_DOMAIN_NONE, 0).
-define(HLS_DOMAIN_FENCE, 1).
-define(HLS_DOMAIN_RESET, 2).
-define(HLS_DOMAIN_INITIALIZE, 3).
-define(HLS_DOMAIN_PUBLISH, 4).

%% Domain causes are a separate namespace from compiler failure/site codes.
%% Native reasons or hardware source-site metadata remain in endpoint diagnostics.
-define(HLS_DOMAIN_FAULT_ACTOR, 1).
-define(HLS_DOMAIN_FAULT_OWNER, 2).
-define(HLS_DOMAIN_FAULT_INITIALIZATION, 3).
-define(HLS_DOMAIN_FAULT_LIFECYCLE, 4).
-define(HLS_DOMAIN_FAULT_PROTOCOL, 5).

%% Current incarnation and one live/last lifecycle transition, never application history.
-record(domain_state, {
    phase = ?HLS_DOMAIN_UNBOUND :: hls_nums:uN(3),
    current = 0 :: hls_nums:u64(),
    previous = 0 :: hls_nums:u64(),
    target = 0 :: hls_nums:u64(),
    transition = 0 :: hls_nums:u64(),
    fault = 0 :: hls_nums:u16()
}).

%% Acknowledgements echo the accepted transition triple; faults name current in expected.
-record(domain_input, {
    op = ?HLS_DOMAIN_INSPECT :: hls_nums:uN(4),
    expected = 0 :: hls_nums:u64(),
    target = 0 :: hls_nums:u64(),
    transition = 0 :: hls_nums:u64(),
    fault = 0 :: hls_nums:u16()
}).

%% The adapter drives action once per transition phase and acknowledges completed work.
-record(domain_output, {
    status = ?HLS_DOMAIN_OK :: hls_nums:uN(4),
    action = ?HLS_DOMAIN_NONE :: hls_nums:uN(3),
    admit = false :: boolean(),
    state = #domain_state{} :: #domain_state{}
}).

-endif.
