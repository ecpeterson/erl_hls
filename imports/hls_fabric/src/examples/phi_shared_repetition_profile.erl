-module(phi_shared_repetition_profile).
-moduledoc "Shared placement for the public repetition-code topology.".
-export([profile/1]).
-doc "Shares each family through RAM and offloads phi contribution gathering.".
-spec profile(pos_integer()) -> map().
profile(N) ->
    (phi_repetition_topology:profile(N))#{reduction_placements => #{phi => source_fragments},
        scheduler_groups => maps:from_list([{Family,
            #{members => [{family, Family}], state_storage => block_ram, mailbox_storage => block_ram}}
            || Family <- [data, syndrome, phi]])}.
