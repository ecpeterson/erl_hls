%%%% xls_topology_profile
%%%%
%%%% Physical option and naming policies shared by the topology backends.

-module(xls_topology_profile).
-moduledoc false.

-export([normalize/2, identifier/2, egress_depth/2]).
-export_type([profile/0]).

-define(U32_MAX, 16#ffffffff).

-type egress_policy() :: burst | 0..?U32_MAX.
-type profile() :: #{
    name := atom() | string(),
    channel_depth := 1..?U32_MAX,
    actor_egress_depth := egress_policy(),
    scheduler_groups => map(),
    reduction_placements => map(),
    effect_window_partition => global | weak_components
}.

%% Validate before inserting defaults so scalar profiles continue to reject
%% family-only options. A normalized family profile has every optional key.
-spec normalize(profile(), scalar | family) -> profile().
normalize(Profile, Backend) when is_map(Profile) ->
    Required = [actor_egress_depth, channel_depth, name],
    Keys = lists:sort(maps:keys(Profile)),
    Allowed = Required ++ optional_keys(Backend),
    case {Required -- Keys, Keys -- Allowed} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    #{name := Name0, channel_depth := Depth,
        actor_egress_depth := EgressDepth} = Profile,
    Name = identifier(Name0, topology_name),
    ok = validate_channel_depth(Depth),
    ok = validate_egress_depth(EgressDepth),
    normalize_options(Profile#{name := Name}, Backend);
normalize(Profile, _Backend) ->
    error({invalid_dslx_profile, Profile}).

optional_keys(scalar) -> [];
optional_keys(family) ->
    [effect_window_partition, reduction_placements, scheduler_groups].

validate_channel_depth(Depth)
        when is_integer(Depth), Depth > 0, Depth =< ?U32_MAX -> ok;
validate_channel_depth(Depth) -> error({invalid_dslx_channel_depth, Depth}).

validate_egress_depth(burst) -> ok;
validate_egress_depth(Depth)
        when is_integer(Depth), Depth >= 0, Depth =< ?U32_MAX -> ok;
validate_egress_depth(Depth) -> error({egress_depth, Depth}).

normalize_options(Profile, scalar) -> Profile;
normalize_options(Profile, family) ->
    Groups = map_option(scheduler_groups, Profile),
    Placements = map_option(reduction_placements, Profile),
    Partition = maps:get(effect_window_partition, Profile, global),
    case Partition of
        global -> ok;
        weak_components -> ok;
        _ -> error({effect_window_partition, Partition})
    end,
    Profile#{
        scheduler_groups => Groups,
        reduction_placements => Placements,
        effect_window_partition => Partition
    }.

map_option(Key, Profile) ->
    case maps:get(Key, Profile, #{}) of
        Value when is_map(Value) -> Value;
        Value -> error({Key, Value})
    end.

%% The registered producer already holds one effect; burst reserves only the
%% remaining capacity in the explicit egress FIFO. Literal depths pass through.
-spec egress_depth(egress_policy(), hls_actor_interface:summary()) ->
    non_neg_integer().
egress_depth(burst, Interface) ->
    max(0, hls_actor_interface:max_entry_effects(Interface) - 1);
egress_depth(Depth, _Interface) -> Depth.

-spec identifier(atom() | string(), term()) -> string().
identifier(Name, Context) when is_atom(Name) ->
    identifier(atom_to_list(Name), Context);
identifier(Name, Context) when is_list(Name) ->
    case re:run(Name, "^[a-z][a-z0-9_]*$", [{capture, none}]) of
        match ->
            case lists:member(Name, reserved_identifiers()) of
                true -> error({reserved_dslx_identifier, Context, Name});
                false -> Name
            end;
        nomatch -> error({invalid_dslx_identifier, Context, Name})
    end;
identifier(Name, Context) ->
    error({invalid_dslx_identifier, Context, Name}).

reserved_identifiers() ->
    [
        "as", "const", "else", "enum", "fn", "for", "if", "import",
        "in", "let", "match", "proc", "pub", "spawn", "struct",
        "type", "while"
    ].
