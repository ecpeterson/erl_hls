-ifndef(HLS_DOMAIN_LIFECYCLE_HRL).
-define(HLS_DOMAIN_LIFECYCLE_HRL, true).

%% Lifecycle states; only ready admits application traffic.
-type domain_phase() :: unbound | ready | closing | isolated | initializing | failed | stopped.

%% Management commands and correlated completions; adapters may explicitly reject an envelope.
-type domain_operation() :: inspect | activate | replace | fault | fenced | reset_done | initialized | abort | reject | stop.

%% Command disposition is distinct from completion of the requested physical work.
-type domain_status() :: ok | accepted | replay | stale | busy | invalid | failure | completed.

%% Outstanding backend work; publish occurs only on readiness completion.
-type domain_action() :: none | fence | reset | initialize | publish.

%% Domain causes, separate from numeric compiler failure/site codes in diagnostics.
-type domain_fault() :: none | actor_failure | owner_down | initialization_failure | lifecycle_failure | protocol_failure.

%% Current incarnation and one live/last lifecycle transition, never application history.
-record(domain_state, {
    phase = unbound :: domain_phase(),
    current = 0 :: hls_nums:u64(),
    previous = 0 :: hls_nums:u64(),
    target = 0 :: hls_nums:u64(),
    transition = 0 :: hls_nums:u64(),
    fault = none :: domain_fault()
}).

%% Acknowledgements echo the accepted transition triple; faults name current in expected.
-record(domain_input, {
    op = inspect :: domain_operation(),
    expected = 0 :: hls_nums:u64(),
    target = 0 :: hls_nums:u64(),
    transition = 0 :: hls_nums:u64(),
    fault = none :: domain_fault()
}).

%% The adapter drives action once per transition phase and acknowledges completed work.
-record(domain_output, {
    status = ok :: domain_status(),
    action = none :: domain_action(),
    admit = false :: boolean(),
    state = #domain_state{} :: #domain_state{}
}).

-endif.
