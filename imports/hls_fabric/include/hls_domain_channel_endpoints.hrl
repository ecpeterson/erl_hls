-ifndef(HLS_DOMAIN_CHANNEL_ENDPOINTS_HRL).
-define(HLS_DOMAIN_CHANNEL_ENDPOINTS_HRL, true).

%% Management operations never perform a packet handshake on the same edge.
-type endpoint_operation() :: tick | bind | fence.
%% Unknown remote progress is not a successful retirement or permission to replay.
%% Imported helper signatures currently require an expanded union, not a local alias.
%% Share its member order so remote results and endpoint fields use one atom codec.
-define(HLS_DOMAIN_ENDPOINT_STATUS, ok | accepted | stale | invalid | busy | closed | exhausted).
%% Endpoint admission and lifecycle outcomes share the expanded wire-codec union above.
-type endpoint_status() :: ?HLS_DOMAIN_ENDPOINT_STATUS.

%% The link namespace is distinct from either host-management session. A warm
%% endpoint retains these tombstones; a cold reset needs external namespace exclusion.
-record(endpoint_binding, {
    namespace = 0 :: hls_nums:u64(),
    generation = 0 :: hls_nums:u64(),
    source_incarnation = 0 :: hls_nums:u64(),
    destination_incarnation = 0 :: hls_nums:u64()
}).

%% The outer carrier adds the static directed-channel identity and validates framing.
%% Acknowledgements echo this exact identity, without an application payload.
-record(endpoint_packet, {
    binding = #endpoint_binding{} :: #endpoint_binding{},
    sequence = 0 :: hls_nums:u32()
}).

%% One source publication remains owned through transmission and acknowledgement.
%% The payload and native slot are held once by the external wrapper, not here.
-record(endpoint_tx_state, {
    binding = #endpoint_binding{} :: #endpoint_binding{},
    sequence = 0 :: hls_nums:u32(),
    active = false :: boolean(),
    inflight = false :: boolean(),
    tx_pending = false :: boolean()
}).

%% receiver_binding/active are host-confirmed binding evidence, used only by bind;
%% they are not a synchronous remote-lifecycle input or a lasting liveness promise.
%% data_tx_ready completes immutable whole-packet handoff to retained carrier storage,
%% not first-word acceptance or a physical-wire completion measurement.
-record(endpoint_tx_input, {
    op = tick :: endpoint_operation(),
    binding = #endpoint_binding{} :: #endpoint_binding{},
    receiver_binding = #endpoint_binding{} :: #endpoint_binding{},
    receiver_active = false :: boolean(),
    local_ready = false :: boolean(),
    local_incarnation = 0 :: hls_nums:u64(),
    source_valid = false :: boolean(),
    data_tx_ready = false :: boolean(),
    credit_valid = false :: boolean(),
    credit_packet = #endpoint_packet{} :: #endpoint_packet{}
}).

%% packet names the newly captured publication, or the old offered/inflight one.
%% A true source_take requires the wrapper to capture its payload and native slot.
-record(endpoint_tx_output, {
    status = ok :: endpoint_status(),
    state = #endpoint_tx_state{} :: #endpoint_tx_state{},
    source_take = false :: boolean(),
    tx_valid = false :: boolean(),
    credit_ready = false :: boolean(),
    credit_drop = false :: boolean(),
    packet = #endpoint_packet{} :: #endpoint_packet{}
}).

%% One received publication waits for native capture, then for ACK transmission.
%% Retained sequence suppresses duplicates; there is no replay or ACK retry state.
-record(endpoint_rx_state, {
    binding = #endpoint_binding{} :: #endpoint_binding{},
    sequence = 0 :: hls_nums:u32(),
    active = false :: boolean(),
    buffered = false :: boolean(),
    ack_pending = false :: boolean()
}).

%% Only this endpoint's local lifecycle is sampled. Native capture is independent
%% of network receipt; ack_tx_ready completes immutable whole-ACK handoff to retained carrier storage.
-record(endpoint_rx_input, {
    op = tick :: endpoint_operation(),
    binding = #endpoint_binding{} :: #endpoint_binding{},
    local_ready = false :: boolean(),
    local_incarnation = 0 :: hls_nums:u64(),
    data_valid = false :: boolean(),
    data_packet = #endpoint_packet{} :: #endpoint_packet{},
    destination_ready = false :: boolean(),
    ack_tx_ready = false :: boolean()
}).

%% data_take captures the external payload/slot; destination_take consumes that
%% old retained value. Acknowledgement follows native capture on a later edge.
-record(endpoint_rx_output, {
    status = ok :: endpoint_status(),
    state = #endpoint_rx_state{} :: #endpoint_rx_state{},
    data_ready = false :: boolean(),
    data_take = false :: boolean(),
    data_drop = false :: boolean(),
    destination_valid = false :: boolean(),
    destination_take = false :: boolean(),
    ack_valid = false :: boolean(),
    packet = #endpoint_packet{} :: #endpoint_packet{}
}).
-endif.
