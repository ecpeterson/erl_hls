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
    phi_correction,
    phi_config,
    pauli_query,
    pauli_reply,
    noise_cutoff,
    pauli_update,
    phi_status
]).

-define(PHI_NORTH_MASK, 1).
-define(PHI_EAST_MASK, 2).
-define(PHI_WEST_MASK, 4).
-define(PHI_SOUTH_MASK, 8).
-define(PHI_ALL_DIRECTIONS, 15).
-define(PHENOM_PRESENT_MASK, 1).
-define(PHENOM_QUIET_MASK, 2).

-record(phi, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    values = hls_type:zero() ::
        hls_lists:list(phi_field:field(), 2)
}).

-record(phi0, {
    step = hls_type:zero() :: hls_nums:u32(),
    source = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: phi_field:field()
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
    %% PHENOM_PRESENT_MASK and PHENOM_QUIET_MASK share this wire word.
    flags = hls_type:zero() :: hls_nums:u32()
}).

-record(phenom_anyon, {
    step = hls_type:zero() :: hls_nums:u32(),
    %% PHENOM_PRESENT_MASK and PHENOM_QUIET_MASK share this wire word.
    flags = hls_type:zero() :: hls_nums:u32(),
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

%% One statically provisioned coin stream per logical phi-cell instance.
-record(phi_config, {
    seed = hls_type:zero() :: hls_nums:u32()
}).

%% Inspects one simulator's cumulative physical-error and decoder-correction
%% Pauli frame. The reply is the bit which would flip a measurement in the
%% requested basis. This actor operation is nondestructive classical simulator
%% introspection; a physical memory experiment may use only one basis before
%% reset. The coordinator sends it only after stopping noise and draining
%% decoder correction traffic. Spatial addressing belongs to the topology
%% envelope, not this actor message.
-record(pauli_query, {
    request_id = hls_type:zero() :: hls_nums:u32(),
    measurement = hls_type:zero() :: hls_pauli:pauli()
}).

%% Replies with the anticommutation bit between the requested measurement and
%% the actor's cumulative physical-error and decoder-correction frame.
-record(pauli_reply, {
    request_id = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    anticommutes = hls_type:zero() :: hls_nums:u32()
}).

%% Stops new phenomenological noise beginning with `first_quiet_step`. The
%% command must reach every source before that round's random decision. Quiet
%% bits propagate through data replies, syndrome announcements, and post-move
%% phi status, so the experiment coordinator waits for a complete certified
%% quiet status set before testing convergence. Experiments quiesce before the
%% u32 step counter rolls over.
-record(noise_cutoff, {
    first_quiet_step = hls_type:zero() :: hls_nums:u32()
}).

%% Applies one decoder correction to the addressed data qubit's Pauli frame.
%% The topology adapter translates a `phi_correction` into the destination and
%% Pauli value. Applying the same update twice cancels it, so updates must be
%% delivered at most once until the protocol carries operation identities.
-record(pauli_update, {
    pauli = hls_type:zero() :: hls_pauli:pauli()
}).

%% Reports one phi cell's occupancy after every move for `step` has arrived.
%% On each decoder-plane output, a cell's status follows that cell's optional
%% correction for the same step. A complete all-zero coordinate set therefore
%% proves both that the plane is empty and that its earlier correction events
%% have crossed that output boundary.
-record(phi_status, {
    step = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    %% PHENOM_PRESENT_MASK and PHENOM_QUIET_MASK share this wire word.
    flags = hls_type:zero() :: hls_nums:u32()
}).

-endif.
