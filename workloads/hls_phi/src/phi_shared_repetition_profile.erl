-module(phi_shared_repetition_profile).
-moduledoc """
Workload channel-scheduler placement for the compiler-owned phi_repetition_topology. Extends that logical application profile with shared RAM groups and source-fragment reduction placement; repetition fixtures pass it to the fabric topology backend.
""".
%% Workload shared-scheduler placement.
-export([profile/1]).
-doc "Shares each family through RAM and offloads phi contribution gathering.".
-spec profile(pos_integer()) -> map().
profile(N) ->
    (phi_repetition_topology:profile(N))#{
        reduction_placements => #{phi => source_fragments},
        scheduler_groups => maps:from_list([
            {Family, #{
                members => [{family, Family}],
                state_storage => block_ram,
                mailbox_storage => block_ram
            }}
         || Family <- [data, syndrome, phi]
        ])
    }.
