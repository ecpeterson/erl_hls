-ifndef(HLS_DOMAIN_CHANNEL_HRL).
-define(HLS_DOMAIN_CHANNEL_HRL, true).

%% Lifecycle control is separate from Erlang process linking and application data.
-type channel_operation() :: tick | bind | fence.
%% Rejected binding does not invent endpoint retirement or recover queued application work.
-type channel_status() :: ok | accepted | stale | invalid | busy | closed | exhausted.

%% One packet owns the credit until its exact receiver acknowledgement returns.
%% These fields live outside both endpoint reset regions; closed bindings retain tombstones.
-record(channel_state, {
    source_incarnation = 0 :: hls_nums:u64(),
    destination_incarnation = 0 :: hls_nums:u64(),
    generation = 0 :: hls_nums:u64(),
    sequence = 0 :: hls_nums:u32(),
    active = false :: boolean(),
    inflight = false :: boolean(),
    received = false :: boolean(),
    tx_pending = false :: boolean(),
    ack_pending = false :: boolean()
}).

%% Destination_live is lifecycle readiness; destination_ready is mailbox admission.
%% Packet payload and slot are retained by the wrapper, not copied through this kernel.
-record(channel_input, {
    op = tick :: channel_operation(),
    expected_generation = 0 :: hls_nums:u64(),
    source_incarnation = 0 :: hls_nums:u64(),
    destination_incarnation = 0 :: hls_nums:u64(),
    source_ready = false :: boolean(),
    destination_live = false :: boolean(),
    source_valid = false :: boolean(),
    data_tx_ready = false :: boolean(),
    data_valid = false :: boolean(),
    data_generation = 0 :: hls_nums:u64(),
    data_sequence = 0 :: hls_nums:u32(),
    destination_ready = false :: boolean(),
    ack_tx_ready = false :: boolean(),
    credit_valid = false :: boolean(),
    credit_generation = 0 :: hls_nums:u64(),
    credit_sequence = 0 :: hls_nums:u32()
}).

%% Decisions use old state: capture, transmit, receive, acknowledge and release are distinct edges.
%% Generation/sequence name the outgoing metadata, or the newly captured source packet.
-record(channel_output, {
    status = ok :: channel_status(),
    state = #channel_state{} :: #channel_state{},
    source_take = false :: boolean(),
    tx_valid = false :: boolean(),
    data_ready = false :: boolean(),
    data_drop = false :: boolean(),
    destination_valid = false :: boolean(),
    destination_take = false :: boolean(),
    ack_valid = false :: boolean(),
    credit_ready = false :: boolean(),
    credit_drop = false :: boolean(),
    generation = 0 :: hls_nums:u64(),
    sequence = 0 :: hls_nums:u32()
}).
-endif.
