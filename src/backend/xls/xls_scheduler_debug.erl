-module(xls_scheduler_debug).
-moduledoc "Compiler-owned projections of shared-actor state writes and scheduler metadata.".
-export([projection/3, projection/4, validate/3, actor_key/1]).

%% Emit beside the RTL generated from this exact plan. The instrumentation tool
%% checks RAM interfaces and fingerprints this document with the RTL sources.
%% Artifacts are the exact actor DSLX files passed to XLS, indexed by module.
%% Keys are opaque hashes of logical Erlang IDs; the host never interns atoms
%% or decodes external Erlang terms supplied by a device or manifest.
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => iodata()}) -> map().
projection(Plan, Specs, Artifacts) ->
    projection(Plan, Specs, Artifacts, #{}).

-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => iodata()}, #{mailbox_debug => boolean()}) -> map().
projection(Plan, Specs, Artifacts, Options) ->
    build(Plan, Specs, xls_scheduler_observation:enabled(Options), fun(Module, Origins) ->
        xls_failure_sites:from_artifact(Origins, maps:get(Module, Artifacts))
    end).

%% Runtime binding checks the artifact's canonical codebook against structural
%% BEAM origins. It does not run compiler providers or require deployed source.
%% The verified manifest fingerprint binds the selected subset to the RTL.
-spec validate(hls_topology:plan(), hls_scheduler_plan:spec(), map()) -> ok.
validate(Plan, Specs, Projection = #{<<"banks">> := Banks}) ->
    ByModule = maps:from_list([{M, Fs} || #{<<"module">> := M, <<"failures">> := Fs} <- Banks]),
    MailboxDebug = lists:any(fun(B) -> is_map_key(<<"mailbox">>, B) end, Banks),
    Expected = build(Plan, Specs, MailboxDebug, fun(Module, Origins) ->
        Values = maps:from_keys(maps:values(maps:get(atom_to_binary(Module), ByModule, #{})), true),
        xls_failure_sites:number([O || O <- Origins, is_map_key(json_value(O), Values)])
    end),
    case Projection =:= Expected of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end;
validate(_Plan, _Specs, _Projection) -> error(actor_projection_mismatch).

build(Plan, Specs, MailboxDebug, Codebook) ->
    Scheduler = #{groups := Groups} = hls_scheduler_plan:normalize(Plan, Specs),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Groups]),
    Codebooks = maps:map(fun(Module, #{failure_origins := Origins}) ->
        Codebook(Module, Origins)
    end, Interfaces),
    Banks = [with_mailbox(MailboxDebug, Group,
        bank(Index, Group, maps:get(Module, Interfaces), Placements, maps:get(Module, Codebooks))) ||
        {Index, Group = #{module := Module}} <- lists:enumerate(0, Groups)],
    %% Normalize JSON keys/strings once for exact host-side manifest comparison.
    json_value(#{schema => 3, binding => digest({Plan, Scheduler}), banks => Banks}).

with_mailbox(false, _Group, Bank) -> Bank;
with_mailbox(true, #{mailbox_capacity := Capacity}, Bank = #{index := Index}) ->
    Bank#{mailbox => #{capacity => Capacity, width => 24,
        port => iolist_to_binary(["_scheduler_", integer_to_list(Index), "_mailbox_debug_out"])}}.

bank(Index, #{module := Module, slot_count := Slots, state := #{width := DataWidth},
        reduction_storage_width := ReductionWidth, state_storage := block_ram},
        Interface = #{phases := Phases}, Placements, Sites) ->
    Layout = xls_statem_codegen:shared_machine_layout(DataWidth, ReductionWidth),
    Fields = maps:with([phase, enter_pending, failure], Layout),
    Entries = lists:keysort(1, [{Slot, #{key => actor_key(Id), slot => Slot,
        name => iolist_to_binary(io_lib:format("~p", [Id]))}} ||
        {Id, #{index := I, slot := Slot}} <- maps:to_list(Placements), I =:= Index]),
    Bank = #{index => Index, ram => iolist_to_binary(["scheduler_", integer_to_list(Index), "_state"]),
        slots => Slots, width => maps:get(width, Layout), fields => Fields,
        failures => maps:from_list([{integer_to_binary(Code), maps:remove(code, Site)} ||
            Site = #{code := Code} <- [#{code => C, kind => K} || {C, K} <- xls_failure_sites:generic()] ++ Sites]),
        module => atom_to_binary(Module), phases => [atom_to_binary(P) || P <- Phases], actors => [A || {_, A} <- Entries]},
    with_reduction(maps:get(reductions, Interface, none), Layout, Bank);
bank(Index, _Group, _Interface, _Placements, _Codebook) ->
    error({debug_requires_state_ram, Index}).

with_reduction(none, _Layout, Bank) -> Bank;
with_reduction(Reduction = #{sites := Sites}, #{reduction := #{offset := Start}}, Bank) ->
    Layout = xls_statem_reduction_ir:packed_layout(Reduction),
    Names = [status, site, key, remaining, failure],
    {Width, Fields} = lists:foldl(fun(Name, {Offset, Acc}) ->
        #{offset := Source, width := Bits} = maps:get(Name, Layout),
        {Offset + Bits, Acc#{Name => #{offset => Start + Source, width => Bits,
            observation_offset => 56 + Offset}}}
    end, {0, #{}}, Names),
    Bank#{reduction => #{width => Width, fields => Fields,
        sites => [maps:with([id, phase, name, population], Site) || Site <- Sites]}}.

json_value(Term) -> json:decode(iolist_to_binary(json:encode(Term))).

-spec actor_key(term()) -> binary().
actor_key(Id) -> digest(Id).

digest(Term) ->
    string:lowercase(binary:encode_hex(crypto:hash(sha256,
        term_to_binary(Term, [deterministic])))).
