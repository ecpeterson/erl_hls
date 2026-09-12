-module(xls_scheduler_debug).
-moduledoc "Compiler-owned projections of committed shared-actor state RAM writes.".
-export([projection/2, actor_key/1]).

%% Emit beside the RTL generated from this exact plan. The instrumentation tool
%% checks RAM interfaces and fingerprints this document with the RTL sources.
%% Keys are opaque hashes of logical Erlang IDs; the host never interns atoms
%% or decodes external Erlang terms supplied by a device or manifest.
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec()) -> map().
projection(Plan, Specs) ->
    Scheduler = #{groups := Groups} = hls_scheduler_plan:normalize(Plan, Specs),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Groups]),
    Banks = [bank(Index, Group, maps:get(Module, Interfaces), Placements) ||
        {Index, Group = #{module := Module}} <- lists:enumerate(0, Groups)],
    %% Normalize JSON keys/strings once for exact host-side manifest comparison.
    json:decode(iolist_to_binary(json:encode(#{schema => 2,
        binding => digest({Plan, Scheduler}), banks => Banks}))).

bank(Index, #{module := Module, slot_count := Slots, state := #{width := DataWidth},
        reduction_storage_width := ReductionWidth, state_storage := block_ram},
        #{phases := Phases, failure_sites := Sites}, Placements) ->
    Layout = xls_statem_codegen:shared_machine_layout(DataWidth, ReductionWidth),
    Fields = maps:with([phase, enter_pending, failure], Layout),
    Entries = lists:keysort(1, [{Slot, #{key => actor_key(Id), slot => Slot,
        name => iolist_to_binary(io_lib:format("~p", [Id]))}} ||
        {Id, #{index := I, slot := Slot}} <- maps:to_list(Placements), I =:= Index]),
    #{index => Index, ram => iolist_to_binary(["scheduler_", integer_to_list(Index), "_state"]),
        slots => Slots, width => maps:get(width, Layout), fields => Fields,
        failures => maps:from_list([{integer_to_binary(Code), maps:remove(code, Site)} ||
            Site = #{code := Code} <- [#{code => C, kind => K} || {C, K} <- xls_failure_sites:generic()] ++ Sites]),
        module => atom_to_binary(Module), phases => [atom_to_binary(P) || P <- Phases], actors => [A || {_, A} <- Entries]};
bank(Index, _Group, _Interface, _Placements) ->
    error({debug_requires_state_ram, Index}).

-spec actor_key(term()) -> binary().
actor_key(Id) -> digest(Id).

digest(Term) ->
    string:lowercase(binary:encode_hex(crypto:hash(sha256,
        term_to_binary(Term, [deterministic])))).
