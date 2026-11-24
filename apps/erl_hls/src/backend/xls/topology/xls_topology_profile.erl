%%%% xls_topology_profile
%%%%
%%%% Physical option and naming policies shared by the topology backends.

-module(xls_topology_profile).
-moduledoc "Validates physical options shared by dedicated topology preparation and rendering. It fixes naming, channel/egress capacities, observations and ordinary-frame capacity before xls_topology_graph or family preparation; logical actor identities and callback semantics remain in hls_topology and actor lowering.".

%% Normalize the physical generation contract.
-export([normalize/1]).
%% Resolve checked names and interface-dependent egress capacity.
-export([identifier/2, egress_depth/2]).
-export_type([profile/0]).

%% The common contract accepts a literal depth or one actor effect burst.
-type egress_policy() :: hls_implementation_constraints:egress_policy().
-doc "Physical generation options; logical actor identities and callback semantics remain separate.".
-type profile() :: #{
    name := atom() | string(),
    channel_depth := 1..((1 bsl 32) - 1),
    actor_egress_depth := egress_policy(),
    direct_actor_debug => boolean(),
    frame_payload_words => hls_frame_layout:words()
}.

%% Validate one physical option contract before inserting defaults. Backend
%% capability checks concern the requested operation, not the spelling of
%% otherwise identical placement profiles.
-doc "Validates input structure and bounds before returning a complete normalized plan.".
-spec normalize(profile()) -> profile().
normalize(Profile) when is_map(Profile) ->
    normalize_options(
        hls_implementation_constraints:normalize_topology(
            Profile, [direct_actor_debug], fun identifier/2
        )
    );
normalize(Profile) ->
    error({invalid_dslx_profile, Profile}).

%% Observation is independent of buffering and routing.
-spec normalize_options(profile()) -> profile().
normalize_options(Profile) ->
    Profile#{
        direct_actor_debug => xls_actor_observation:enabled(Profile)
    }.

%% The registered producer already holds one effect; burst reserves only the
%% remaining capacity in the explicit egress FIFO. Literal depths pass through.
-doc "Returns the checked literal egress depth or derives remaining FIFO capacity from the actor's largest effect batch.".
-spec egress_depth(egress_policy(), hls_actor_interface:summary()) ->
    non_neg_integer().
egress_depth(burst, Interface) ->
    hls_implementation_constraints:egress_depth(
        burst, hls_actor_interface:max_entry_effects(Interface)
    );
egress_depth(Depth, _Interface) ->
    hls_implementation_constraints:egress_depth(Depth, 0).

-doc "Validates a lowercase deployment identifier against the shared DSLX keyword set.".
-spec identifier(atom() | string(), term()) -> string().
identifier(Name, Context) when is_atom(Name) ->
    hls_implementation_constraints:identifier(Name, Context, fun reserved/2);
identifier(Name, Context) ->
    hls_implementation_constraints:identifier(Name, Context, fun reserved/2).

%% Ports and endpoint IDs are stems: their emitted identifiers receive suffixes.
%% In particular the ordinary source port `out` never becomes bare DSLX `out`.
-spec reserved(string(), term()) -> boolean().
reserved(Name, Context) ->
    hls_implementation_constraints:reserved_identifier(
        Name, Context, fun xls_names:keyword/1, [], []
    ).
