%%%% Shared wire schema for the phi and phenomenological-noise examples.
%%%%
%%%% Message tag order is part of the wire ABI.  Every independently lowered
%%%% actor in this example includes this complete schema so a frame emitted by
%%%% one module has the same numeric tag at every receiver.
%%%%
%%%% This shared table is a bridge for an example whose actors are compiled
%%%% separately, not a requirement that all fabric tags become global.  A
%%%% topology-aware elaborator can instead encode each outgoing message using
%%%% the destination actor's locally owned receive table.  Forwarding actors
%%%% need a broader identity only when their possible downstream receivers
%%%% cannot be closed over at compile time.

-ifndef(PHI_PROTOCOL_HRL).
-define(PHI_PROTOCOL_HRL, true).

-define(PHI_PROTOCOL_TAGS, [
    phi,
    anyon_move,
    phi0,
    phenom_config,
    phenom_request,
    phenom_query,
    phenom_data,
    phenom_anyon
]).

-define(PHI_NORTH_MASK, 1).
-define(PHI_EAST_MASK, 2).
-define(PHI_WEST_MASK, 4).
-define(PHI_SOUTH_MASK, 8).
-define(PHI_ALL_DIRECTIONS, 15).

-record(phi, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), 2)
}).

-record(phi0, {
    step = xls_type:zero() :: xls_nums:u32(),
    source = xls_type:zero() :: xls_nums:u32(),
    value = xls_type:zero() :: xls_nums:u32()
}).

-record(anyon_move, {
    step = xls_type:zero() :: xls_nums:u32(),
    present = xls_type:zero() :: xls_nums:u32()
}).

-record(phenom_config, {
    seed = xls_type:zero() :: xls_nums:u32(),
    threshold = xls_type:zero() :: xls_nums:u32()
}).

-record(phenom_request, {
    step = xls_type:zero() :: xls_nums:u32()
}).

-record(phenom_query, {
    step = xls_type:zero() :: xls_nums:u32(),
    source = xls_type:zero() :: xls_nums:u32()
}).

-record(phenom_data, {
    step = xls_type:zero() :: xls_nums:u32(),
    source = xls_type:zero() :: xls_nums:u32(),
    present = xls_type:zero() :: xls_nums:u32()
}).

-record(phenom_anyon, {
    step = xls_type:zero() :: xls_nums:u32(),
    present = xls_type:zero() :: xls_nums:u32()
}).

-endif.
