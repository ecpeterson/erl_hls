%%%% Shared configuration for the decoder-only profiling fixture.
-module(phi_decoder_profile).
-moduledoc """
Bounded geometry and executor choices for decoder-only measurements.

`shape` counts phi cells per plane, not physical qubits. The default `[3,3]`
with both planes has eighteen phi actors. The kernel retains its two stored
field layers and twelve diffusion rounds at every shape; these profiles
measure a fixed workload, not a distance-dependent decoder algorithm.
""".

-export([normalize/1, planes/1, manifest/1]).

-doc "Validates profile options and fills defaults, with canonical plane order.".
-spec normalize(pos_integer() | map()) -> map().
normalize(Shards) when is_integer(Shards) ->
    normalize(#{shards => Shards});
normalize(Options) when is_map(Options) ->
    case maps:keys(Options) -- [shape, planes, shards] of
        [] -> ok;
        Unknown -> error({unknown_profile_options, Unknown})
    end,
    Shape = maps:get(shape, Options, [3, 3]),
    case Shape of
        [W, H] when is_integer(W), W > 0, W =< 50,
                    is_integer(H), H > 0, H =< 50 -> ok;
        _ -> error({invalid_profile_shape, Shape})
    end,
    Selected = maps:get(planes, Options, [x, z]),
    case Selected of
        [x] -> ok;
        [z] -> ok;
        [x, z] -> ok;
        [z, x] -> ok;
        _ -> error({invalid_profile_planes, Selected})
    end,
    [Width, Height] = Shape,
    Shards = maps:get(shards, Options, min(3, Width * Height)),
    case Shards of
        N when is_integer(N), N > 0, N =< Width * Height, N =< 32 -> ok;
        _ -> error({invalid_profile_shards, Shards, Shape})
    end,
    #{shape => Shape, planes => lists:sort(Selected), shards => Shards}.

%% Keep family seed blocks stable when the other plane is omitted.
-spec planes(map()) -> [map()].
planes(#{planes := Selected}) ->
    [Plane || Plane = #{id := Id} <- [
        #{id => x, phi => phi_x, source => syndrome_x,
            events => x_decoder_events, source_seed => 0, phi_seed => 2},
        #{id => z, phi => phi_z, source => syndrome_z,
            events => z_decoder_events, source_seed => 1, phi_seed => 3}
    ], lists:member(Id, Selected)].

-doc "Describes the generated population without inferring board placement.".
-spec manifest(pos_integer() | map()) -> map().
manifest(Options) ->
    #{shape := [Width, Height], planes := Planes, shards := Shards} =
        normalize(Options),
    Count = length(Planes),
    #{width => Width, height => Height, planes => Planes,
        shards_per_plane => Shards, scheduler_count => Count * (1 + Shards),
        source_scheduler_count => Count, phi_actor_count => Count * Width * Height,
        source_actor_count => Count * Width * Height}.
