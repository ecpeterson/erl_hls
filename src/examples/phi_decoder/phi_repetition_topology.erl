-module(phi_repetition_topology).
-moduledoc """
Periodic phase-flip repetition code with N data qubits and N weight-two checks.

The physical line alternates data[X], syndrome[X], data[X+1]. Each X check
feeds one phi cell; corrections apply Z to the intervening data qubit. Only
east/west edges exist. N counts data qubits (and checks), not both combined.
N=2 retains two labelled edges between the same phi neighbors; N>=3 gives
those directions distinct recipients. The noise model has independent data-Z
and measurement Bernoulli faults, with the same configured threshold.

The control router accepts data Pauli queries/updates and whole-line noise
cutoff. Decoder correction/status events and data measurements leave through
typed boundaries. A host applies corrections as Pauli updates; the topology
alone is a live workload, not a complete logical-memory experiment. Open
boundaries and their absorption rules are intentionally a separate geometry.
""".
-include("phi_protocol.hrl").
-export([topology/1, topology/2, profile/1, correction_update/2]).

-doc "Returns a periodic line with an exercise noise threshold of one half.".
-spec topology(pos_integer()) -> hls_topology:spec().
topology(N) -> topology(N, 16#80000000).

-doc "Returns the line topology at an explicit u32 data/measurement noise threshold.".
-spec topology(pos_integer(), hls_nums:u32()) -> hls_topology:spec().
topology(N, Threshold) when is_integer(N), N >= 2, N =< 16#ffff,
    is_integer(Threshold), Threshold >= 0, Threshold =< 16#ffffffff ->
    Shape = [N, 1],
    Families = [{data, phenom_line_data_cell},
        {syndrome, phenom_line_syndrome_cell}, {phi, phi_line_cell}],
    #{version => 1, actors => #{},
      families => maps:from_list([{Name, #{module => Module, shape => Shape}}
          || {Name, Module} <- Families]),
      ingresses => [{control_router, {rectangle, Shape}, [
          {data, [pauli_query, pauli_update], [{family, data, {embed, [1, 1], [0, 0]}}]},
          {noise, [noise_cutoff], [{family, data, {embed, [1, 1], [0, 0]}},
              {family, syndrome, {embed, [1, 1], [0, 0]}}]}
      ]}],
      externals => [{decoder_events, out, [phi_correction, phi_status]},
          {data_measurements, out, [pauli_reply]}],
      routes => [], route_relations => [
          relation(phi, east, phi, 1), relation(phi, west, phi, -1),
          relation(phi, syndrome, syndrome, 0),
          {{phi, correction}, [{external, decoder_events}]},
          {{phi, status}, [{external, decoder_events}]},
          relation(syndrome, east, data, 1), relation(syndrome, west, data, 0),
          relation(syndrome, phi, phi, 0),
          relation(data, east, syndrome, 0), relation(data, west, syndrome, -1),
          {{data, measurement}, [{external, data_measurements}]}
      ],
      startup => lists:append([
          [{{Family, X, 0}, [#phenom_config{
              seed = seed(Index, N, X), threshold = Threshold, x = X, y = 0}]}
              || X <- lists:seq(0, N-1)]
          || {Family, Index} <- [{data, 0}, {syndrome, 1}]
      ]) ++ [{{phi, X, 0}, [#phi_config{seed = seed(2, N, X)}]}
          || X <- lists:seq(0, N-1)]};
topology(_N, _Threshold) -> error(badarg).

-doc "Returns dedicated actor placement for a periodic repetition-code line.".
-spec profile(pos_integer()) -> xls_topology_dslx:profile().
profile(N) ->
    _ = topology(N),
    #{name => phi_repetition_topology, channel_depth => 1, actor_egress_depth => burst}.

-doc "Returns the data coordinate and Z update for one decoder move.".
-spec correction_update(#phi_correction{}, pos_integer()) ->
    {{non_neg_integer(), 0}, hls_pauli:pauli()}.
correction_update(#phi_correction{x = X, y = 0, direction = Direction}, N)
    when N >= 2, N =< 16#ffff, X >= 0, X < N ->
    case Direction of
        ?PHI_EAST_MASK -> {{(X+1) rem N, 0}, hls_pauli:z()};
        ?PHI_WEST_MASK -> {{X, 0}, hls_pauli:z()};
        _ -> error(badarg)
    end;
correction_update(_Correction, _N) -> error(badarg).

%% Preserve labelled east/west edges even when their destination PIDs coincide.
-spec relation(atom(), atom(), atom(), integer()) -> tuple().
relation(Source, Port, Destination, Offset) ->
    {{Source, Port}, [{family, Destination, {translate, [Offset, 0], wrap}}]}.

%% Distinct nonzero streams for every actor in the supported small examples.
-spec seed(non_neg_integer(), pos_integer(), non_neg_integer()) -> hls_nums:u32().
seed(Family, N, X) -> ((Family * N + X + 1) * 16#9e3779b9) band 16#ffffffff.
