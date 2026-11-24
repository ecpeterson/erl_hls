%%%% xls_fabric_topology_profile
%%%%
%%%% Physical option and naming policies shared by the topology backends.

-module(xls_fabric_topology_profile).
-moduledoc "Normalizes physical placement and queue policy for fabric topology generation. The build facade and generation planner use this checked profile before backend selection; logical topology and actor semantics remain separate, and these fields describe the current XLS execution model.".

%% Build profile normalization.
-export([normalize/1]).

%% Checked names and per-actor queue policy.
-export([identifier/2, egress_depth/2]).

-export_type([profile/0]).

%% Explicit queue depth or a depth derived from the actor's largest effect batch.
-type egress_policy() :: hls_implementation_constraints:egress_policy().
-doc "Physical generation options; logical actor identities and callback semantics remain separate.".
-type profile() :: #{
    name := atom() | string(),
    channel_depth := 1..((1 bsl 32) - 1),
    actor_egress_depth := egress_policy(),
    scheduler_groups => map(),
    mailbox_debug => boolean(),
    direct_actor_debug => boolean(),
    reduction_placements => map(),
    direct_collections => #{module() => exclusive_epoch},
    effect_window_partition => global | weak_components,
    effect_delivery_width => 1..6,
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
            Profile,
            [
                effect_window_partition,
                reduction_placements,
                scheduler_groups,
                mailbox_debug,
                direct_actor_debug,
                direct_collections,
                effect_delivery_width
            ],
            fun identifier/2
        )
    );
normalize(Profile) ->
    error({invalid_dslx_profile, Profile}).

%% Validates optional placement and observation settings before adding defaults.
-spec normalize_options(map()) -> map().
normalize_options(Profile) ->
    Groups = map_option(scheduler_groups, Profile),
    Placements = map_option(reduction_placements, Profile),
    Partition = maps:get(effect_window_partition, Profile, global),
    case Partition of
        global -> ok;
        weak_components -> ok;
        _ -> error({effect_window_partition, Partition})
    end,
    Width = maps:get(effect_delivery_width, Profile, 1),
    case Width of
        W when is_integer(W), W >= 1, W =< 6 -> ok;
        _ -> error({effect_delivery_width, Width})
    end,
    Profile#{
        effect_delivery_width => Width,
        mailbox_debug => xls_scheduler_observation:enabled(Profile),
        direct_actor_debug => xls_actor_observation:enabled(Profile),
        scheduler_groups => Groups,
        reduction_placements => Placements,
        direct_collections => map_option(direct_collections, Profile),
        effect_window_partition => Partition
    }.

%% Reads a map-valued profile option and rejects another representation.
-spec map_option('reduction_placements' | 'scheduler_groups' | 'direct_collections', map()) ->
    map().
map_option(Key, Profile) ->
    case maps:get(Key, Profile, #{}) of
        Value when is_map(Value) -> Value;
        Value -> error({Key, Value})
    end.

%% The registered producer already holds one effect; burst reserves only the
%% remaining capacity in the explicit egress FIFO. Literal depths pass through.
-doc "Returns the configured queue depth, deriving burst capacity when requested.".
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
        Name,
        Context,
        fun xls_names:keyword/1,
        [scheduler, scheduler_module],
        ["frame_queue", "effect_window", "retained_mux"]
    ).
