%%%% Shared wire schema for the phi and phenomenological-noise examples.
%%%%
%%%% This header declares the shared hls_tags block as well as its records.
%%%% Repeated hls_tags blocks concatenate in include-expanded source order, so
%%%% this header's position is part of the wire ABI.  Every independently
%%%% lowered actor includes it at the same position so a frame emitted by one
%%%% module has the same numeric tag at every receiver.
%%%%
%%%% This shared table is a bridge for an example whose actors are compiled
%%%% separately, not a requirement that all fabric tags become global.  A
%%%% topology-aware elaborator can instead encode each outgoing message using
%%%% the destination actor's locally owned receive table.  Forwarding actors
%%%% need a broader identity only when their possible downstream receivers
%%%% cannot be closed over at compile time.

-ifndef(PHI_PROTOCOL_HRL).
-define(PHI_PROTOCOL_HRL, true).

-hls_tags([
    phi,
    anyon_move,
    phi0,
    phenom_config,
    phenom_request,
    phenom_query,
    phenom_data,
    phenom_anyon,
    phi_correction
]).

-define(PHI_NORTH_MASK, 1).
-define(PHI_EAST_MASK, 2).
-define(PHI_WEST_MASK, 4).
-define(PHI_SOUTH_MASK, 8).
-define(PHI_ALL_DIRECTIONS, 15).

-record(phi, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    values = hls_type:zero() ::
        hls_lists:list(hls_nums:u32(), 2)
}).

-record(phi0, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(anyon_move, {
    step = hls_type:zero() :: hls_nums:u32(),
    present = hls_type:zero() :: hls_nums:u32()
}).

-record(phenom_config, {
    seed = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

-record(phenom_request, {
    step = hls_type:zero() :: hls_nums:u32()
}).

-record(phenom_query, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32()
}).

-record(phenom_data, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32(),
    present = hls_type:zero() :: hls_nums:u32()
}).

-record(phenom_anyon, {
    step = hls_type:zero() :: hls_nums:u32(),
    present = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

%% A provisional sparse correction boundary event. The output stream identifies
%% the decoder plane; x/y name a syndrome location, and direction selects its
%% neighboring data-qubit edge. A valid event always has a nonzero direction.
-record(phi_correction, {
    step = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    direction = hls_type:zero() :: hls_nums:u32()
}).

-endif.
