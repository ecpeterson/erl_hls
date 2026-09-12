-module(xls_scheduler_debug).
-moduledoc "Compiler-owned projections of committed shared-actor state RAM writes.".
-export([projection/3, validate/3, actor_key/1]).

%% Emit beside the RTL generated from this exact plan. The instrumentation tool
%% checks RAM interfaces and fingerprints this document with the RTL sources.
%% Artifacts are the exact actor DSLX files passed to XLS, indexed by module.
%% Keys are opaque hashes of logical Erlang IDs; the host never interns atoms
%% or decodes external Erlang terms supplied by a device or manifest.
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => iodata()}) -> map().
projection(Plan, Specs, Artifacts) ->
    build(Plan, Specs, fun(Module, Origins) ->
        xls_failure_sites:from_artifact(Origins, maps:get(Module, Artifacts))
    end).

%% Runtime binding checks the artifact's canonical codebook against structural
%% BEAM origins. It does not run compiler providers or require deployed source.
%% The verified manifest fingerprint binds the selected subset to the RTL.
-spec validate(hls_topology:plan(), hls_scheduler_plan:spec(), map()) -> ok.
validate(Plan, Specs, Projection = #{<<"banks">> := Banks}) ->
    ByModule = maps:from_list([{M, Fs} || #{<<"module">> := M, <<"failures">> := Fs} <- Banks]),
    Expected = build(Plan, Specs, fun(Module, Origins) ->
        Values = maps:from_keys(maps:values(maps:get(atom_to_binary(Module), ByModule, #{})), true),
        xls_failure_sites:number([O || O <- Origins, is_map_key(json_value(O), Values)])
    end),
    case Projection =:= Expected of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end;
validate(_Plan, _Specs, _Projection) -> error(actor_projection_mismatch).

build(Plan, Specs, Codebook) ->
    Scheduler = #{groups := Groups} = hls_scheduler_plan:normalize(Plan, Specs),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Groups]),
    Codebooks = maps:map(fun(Module, #{failure_origins := Origins}) ->
        Codebook(Module, Origins)
    end, Interfaces),
    Banks = [bank(Index, Group, maps:get(Module, Interfaces), Placements, maps:get(Module, Codebooks)) ||
        {Index, Group = #{module := Module}} <- lists:enumerate(0, Groups)],
    %% Normalize JSON keys/strings once for exact host-side manifest comparison.
    json_value(#{schema => 2, binding => digest({Plan, Scheduler}), banks => Banks}).

bank(Index, #{module := Module, slot_count := Slots, state := #{width := DataWidth},
        reduction_storage_width := ReductionWidth, state_storage := block_ram},
        #{phases := Phases}, Placements, Sites) ->
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
bank(Index, _Group, _Interface, _Placements, _Codebook) ->
    error({debug_requires_state_ram, Index}).

json_value(Term) -> json:decode(iolist_to_binary(json:encode(Term))).

-spec actor_key(term()) -> binary().
actor_key(Id) -> digest(Id).

digest(Term) ->
    string:lowercase(binary:encode_hex(crypto:hash(sha256,
        term_to_binary(Term, [deterministic])))).
