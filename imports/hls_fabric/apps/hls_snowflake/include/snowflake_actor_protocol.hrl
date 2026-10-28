%% Build-time probe; ordinary phase-by-phase coordination remains the default.
-ifndef(SNOWFLAKE_LOCAL_ADVANCE).
-define(SNOWFLAKE_LOCAL_ADVANCE, false).
-endif.

%% Select one compiled protocol without keeping unreachable alternatives in type analysis.
-if(?SNOWFLAKE_LOCAL_ADVANCE).
-define(SF_ADVANCE_SELECT(Advanced, Coordinated), Advanced).
-else.
-define(SF_ADVANCE_SELECT(Advanced, Coordinated), Coordinated).
-endif.

%% Complete decoder traffic; geometry is configuration, never a hardware transition schedule.
-include("snowflake_node.hrl").

%% Connected actors share the current topology transport's selector assignments.
-hls_tags([sf_geometry, sf_vertex_config, sf_coordinator_config, sf_ready,
    sf_input, sf_phase, sf_snapshot, sf_transfer, sf_shift, sf_done,
    sf_correction, sf_round, sf_barrier_config]).

%% Global CID translation constants, sent before each vertex's local configuration.
-record(sf_geometry, {
    boundary_limit = hls_type:zero() :: hls_nums:s32(),
    boundary_shift = hls_type:zero() :: hls_nums:s32(),
    bulk_shift = hls_type:zero() :: hls_nums:s32()
}).
%% A vertex's fixed connectivity and unique correction ownership.
-record(sf_vertex_config, {
    source = hls_type:zero() :: hls_nums:u8(),
    id = hls_type:zero() :: hls_nums:s32(),
    neighbors = hls_type:zero() :: hls_nums:u8(),
    syndrome_bit = hls_type:zero() :: hls_nums:u8(),
    retire_mask = hls_type:zero() :: hls_nums:u8(),
    height = hls_type:zero() :: hls_nums:u8(),
    top = hls_type:zero() :: hls_bool:bool(),
    bottom = hls_type:zero() :: hls_bool:bool(),
    boundary = hls_type:zero() :: hls_bool:bool(),
    below = hls_type:zero() :: hls_bool:bool()
}).
%% The coordinator's finite barrier population and correction warmup horizon.
-record(sf_coordinator_config, {
    count = hls_type:zero() :: hls_nums:u16(),
    height = hls_type:zero() :: hls_nums:u8()
}).
%% Completion of per-vertex startup; source identities detect duplicates.
-record(sf_ready, {source = hls_type:zero() :: hls_nums:u8()}).
%% One independently offered syndrome sheet for the bounded small-window baseline.
-record(sf_input, {
    sheet = hls_type:zero() :: hls_nums:u32(),
    mask = hls_type:zero() :: hls_nums:u32()
}).
%% Coordinator-selected phase: 0=drop, 1/2=whole grow/merge, 3/4=half grow/merge.
-record(sf_phase, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    kind = hls_type:zero() :: hls_nums:u8(),
    mask = hls_type:zero() :: hls_nums:u32()
}).
%% Immutable neighbor state; direction names the sender as seen by the recipient.
-record(sf_snapshot, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    direction = hls_type:zero() :: hls_nums:u8(),
    node = hls_type:zero() :: #node{}
}).
%% A completed neighbor proposal; outgoing is the sender's transfer direction.
-record(sf_transfer, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    direction = hls_type:zero() :: hls_nums:u8(),
    outgoing = hls_type:zero() :: hls_nums:u8()
}).
%% Time-window movement copies the layer above, including its incident edge replicas.
-record(sf_shift, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    node = hls_type:zero() :: #node{},
    growth = hls_type:zero() :: hls_nums:uN(12),
    correction = hls_type:zero() :: hls_nums:uN(6)
}).
%% Barrier acknowledgment covers committed vertex and incident-edge state.
-record(sf_done, {
    source = hls_type:zero() :: hls_nums:u8(),
    epoch = hls_type:zero() :: hls_nums:u32(),
    kind = hls_type:zero() :: hls_nums:u8(),
    busy = hls_type:zero() :: hls_bool:bool()
}).
%% One site's ordered retired correction bits; config selects the owned directions.
-record(sf_correction, {
    sheet = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u8(),
    edges = hls_type:zero() :: hls_nums:uN(6)
}).
%% All vertex commits for the incoming sheet have completed, including quiet sheets.
-record(sf_round, {
    sheet = hls_type:zero() :: hls_nums:u32(),
    epoch = hls_type:zero() :: hls_nums:u32()
}).
%% A completion barrier combines a contiguous group of at most six vertices.
-record(sf_barrier_config, {
    source = hls_type:zero() :: hls_nums:u8(),
    first = hls_type:zero() :: hls_nums:u8(),
    count = hls_type:zero() :: hls_nums:u8()
}).

%% Opt-in actor-owned acknowledgments; the physical receiver is selected separately.
-ifndef(SNOWFLAKE_ACK_REDUCTION).
-define(SNOWFLAKE_ACK_REDUCTION, false).
-endif.
-ifndef(SNOWFLAKE_BARRIER_SOURCES).
-define(SNOWFLAKE_BARRIER_SOURCES, 255).
-endif.
%% Kind bits retain disagreement until completion; busy is a commutative OR.
-record(ack_sum, {kinds = hls_type:zero() :: hls_nums:u8(),
    busy = hls_type:zero() :: hls_bool:bool()}).
