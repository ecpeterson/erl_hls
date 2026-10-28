-module(xls_scheduler_debug).
-moduledoc "Compiler-owned projections of committed actor state and scheduler metadata.".
-export([projection/2, projection/3, projection/4, validate/3]).

-doc "Builds the actor observation map from a retained generation plan and its matching actor artifacts. Uses that plan's observation options, scheduler and checked interfaces without reading sources or redoing placement.".
-spec projection(xls_fabric_topology_dslx:plan(), #{module() => xls_emitted:artifact()}) -> map().
projection(Prepared, Artifacts) ->
    Analysis = #{profile := Options} = xls_fabric_topology_dslx:analysis(Prepared),
    build(Analysis, Options, fun(Module, Locations) ->
        xls_emitted:sites(maps:get(Module, Artifacts), Locations)
    end).

%% Emit beside the RTL generated from this exact plan. The instrumentation tool
%% checks RAM interfaces and fingerprints this document with the RTL sources.
%% Artifacts retain the exact actor DSLX bytes and allocated codebooks, indexed by module.
%% Keys are opaque hashes of logical Erlang IDs; the host never interns atoms
%% or decodes external Erlang terms supplied by a device or manifest.
-doc "Builds the physical actor observation map from matching topology and generated artifacts.".
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => xls_emitted:artifact()}) -> map().
projection(Plan, Specs, Artifacts) ->
    projection(Plan, Specs, Artifacts, #{}).

-doc "Builds the physical actor observation map from matching topology and generated artifacts.".
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => xls_emitted:artifact()}, #{mailbox_debug => boolean(), direct_actor_debug => boolean(), direct_collections => #{module() => exclusive_epoch},
        frame_payload_words => hls_frame_layout:words()}) -> map().
projection(Plan, Specs, Artifacts, Options) ->
    build(prepare(Plan, Specs, Options), Options, fun(Module, Locations) ->
        xls_emitted:sites(maps:get(Module, Artifacts), Locations)
    end).

%% Runtime binding checks the artifact's canonical codebook against structural
%% BEAM origins. It does not run compiler providers or require deployed source.
%% The verified manifest fingerprint binds the selected subset to the RTL.
-doc "Checks projection identity, layouts and failure catalogs against the current build.".
-spec validate(hls_topology:plan(), hls_scheduler_plan:spec(), map()) -> ok.
validate(Plan, Specs, Projection = #{<<"banks">> := Shared}) ->
    Banks = Shared ++ maps:get(<<"direct">>, Projection, []),
    ByModule = maps:from_list([{M, Fs} || #{<<"module">> := M, <<"failures">> := Fs} <- Banks]),
    MailboxDebug = lists:any(fun(B) -> is_map_key(<<"mailbox">>, B) end, Shared),
    Words = maps:get(<<"frame_payload_words">>, Projection, 3),
    Analysis = #{scheduler := Scheduler, interfaces := Interfaces} =
        prepare(Plan, Specs, #{frame_payload_words => Words}),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Direct = xls_actor_observation:bindings(Plan, Placements, Interfaces),
    Policies = maps:from_list([{M, exclusive_epoch} || #{module := M} <- Direct,
        B <- maps:get(<<"direct">>, Projection, []), maps:get(<<"module">>, B) =:= atom_to_binary(M),
        maps:get(<<"early_collection">>, maps:get(<<"reduction">>, B, #{}), false)]),
    Options = #{mailbox_debug => MailboxDebug, direct_actor_debug => maps:is_key(<<"direct">>, Projection),
        direct_collections => Policies, frame_payload_words => Words},
    Expected = build(Analysis, Options, fun(Module, Locations) ->
        try xls_failure_sites:from_catalog(Locations, maps:get(atom_to_binary(Module), ByModule, #{}))
        catch error:_ -> error(actor_projection_mismatch) end
    end),
    case Projection =:= Expected of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end;
validate(_Plan, _Specs, _Projection) -> error(actor_projection_mismatch).

%% Fresh host validation and convenience projection each acquire one current interface catalog.
-spec prepare(hls_topology:plan(), hls_scheduler_plan:spec(), map()) -> map().
prepare(Topology, Specs, Options) ->
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
    Interfaces = hls_scheduler_plan:interfaces(Topology, Layout),
    Scheduler = hls_scheduler_plan:normalize(Topology, Specs, Layout, Interfaces),
    #{topology => Topology, scheduler => Scheduler, interfaces => Interfaces}.

%% Combine only observed modules' codebooks with the retained physical ownership.
-spec build(#{topology := hls_topology:plan(), scheduler := hls_scheduler_plan:plan(),
    interfaces := #{module() => hls_actor_interface:summary()},
    profile => xls_fabric_topology_profile:profile()}, map(),
    fun((module(), [xls_failure_sites:location()]) -> [map()])) -> map().
build(#{topology := Plan, scheduler := Scheduler = #{groups := Groups},
        interfaces := Catalog}, Options, Codebook) ->
    MailboxDebug = xls_scheduler_observation:enabled(Options),
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Direct = case xls_actor_observation:enabled(Options) of
        true -> xls_actor_observation:bindings(Plan, Placements, Catalog);
        false -> []
    end,
    Interfaces = maps:with(lists:usort([M || #{module := M} <- Groups ++ Direct]), Catalog),
    Codebooks = maps:map(fun(Module, #{failure_locations := Locations}) ->
        Codebook(Module, Locations)
    end, Interfaces),
    Banks = [with_mailbox(MailboxDebug, Group,
        bank(Index, Group, maps:get(Module, Interfaces), Placements, maps:get(Module, Codebooks))) ||
        {Index, Group = #{module := Module}} <- lists:enumerate(0, Groups)],
    %% Normalize JSON keys/strings once for exact host-side manifest comparison.
    Schema = case lists:any(fun(G) -> maps:get(admission_reductions, G, false) =/= false orelse
        maps:get(gathers, G, none) =/= none end, Groups) of true -> 5; false -> 4 end,
    Policies = maps:get(direct_collections, Options, #{}),
    Binding = case map_size(Policies) of 0 -> {Plan, Scheduler}; _ -> {Plan, Scheduler, Policies} end,
    BaseProjection = #{schema => Schema, binding => xls_actor_debug:actor_key(Binding), banks => Banks},
    Projection = case hls_frame_layout:payload_words(Layout) of
        3 -> BaseProjection;
        Words -> BaseProjection#{frame_payload_words => Words}
    end,
    json_value(case xls_actor_observation:enabled(Options) of
        false -> Projection;
        true -> Projection#{direct => [direct_bank(Index, Actor,
            maps:get(Module, Interfaces), maps:get(Module, Codebooks), maps:get(Module, Policies, false)) ||
            {Index, Actor = #{module := Module}} <- lists:enumerate(length(Banks), Direct)]}
    end).

%% Direct collectors share the existing observation layout; open with zero
%% remaining distinguishes early input until expected membership is known.
-spec direct_bank(non_neg_integer(), map(), map(), [map()], false | exclusive_epoch) -> map().
direct_bank(Index, Actor, Interface, Codebook, Policy) ->
    Bank = xls_actor_debug:direct_bank(Index, Actor, Interface, Codebook),
    case Policy of
        false -> Bank;
        exclusive_epoch ->
            Bank#{reduction := (maps:get(reduction, Bank))#{early_collection => true}}
    end.

%% Adds sampled mailbox metadata when the selected backend exports it.
-spec with_mailbox(boolean(),map(),map()) -> map().
with_mailbox(false, _Group, Bank) -> Bank;
with_mailbox(true, #{mailbox_capacity := Capacity}, Bank = #{index := Index}) ->
    Bank#{mailbox => #{kind => shared, capacity => Capacity, width => 24,
        port => iolist_to_binary(["_scheduler_", integer_to_list(Index), "_mailbox_debug_out"])}}.

%% Describe observation fields without truncating optional private RAM storage.
-spec bank(non_neg_integer(), map(), map(), map(), [map()]) -> map().
bank(Index, #{module := Module, slot_count := Slots, state_storage := block_ram} = Group,
        Interface = #{phases := Phases}, Placements, Sites) ->
    Layout = xls_machine_layout:from_group(Group),
    Fields = maps:with([phase, enter_pending, failure], xls_machine_layout:fields(Layout)),
    Entries = lists:keysort(1, [{Slot, #{key => xls_actor_debug:actor_key(Id), slot => Slot,
        name => iolist_to_binary(io_lib:format("~p", [Id]))}} ||
        {Id, #{index := I, slot := Slot}} <- maps:to_list(Placements), I =:= Index]),
    Bank = #{index => Index, ram => iolist_to_binary(["scheduler_", integer_to_list(Index), "_state"]),
        slots => Slots, width => xls_machine_layout:width(Layout), fields => Fields,
        failures => xls_actor_debug:failures(Sites),
        module => atom_to_binary(Module), phases => [atom_to_binary(P) || P <- Phases], actors => [A || {_, A} <- Entries]},
    Observed = case maps:find(state_projection, Group) of
        error -> Bank;
        {ok, Projection = #{rows := Rows}} ->
            Local = Projection#{rows := [R || R = #{instance := I} <- Rows, I =:= Index]},
            Bank#{state_projection => xls_state_projection:manifest(Local)}
    end,
    Gathered = maps:get(gathers, Interface, none) =/= none,
    Reduced = case Gathered of
        true -> Observed#{reduction => xls_collection_observation:layout(Interface)};
        false -> with_reduction(maps:get(reductions, Interface, none), Layout, Observed)
    end,
    Policy = maps:get(admission_reductions, Group, false),
    Tagged = case Policy of
        exclusive_epoch -> Reduced#{reduction := (maps:get(reduction, Reduced))#{early_collection => true}};
        _ -> Reduced
    end,
    case {Policy, Gathered} of
        {false, false} -> Tagged;
        _ ->
            Width = case Gathered of
                true -> xls_collection_observation:width(Interface);
                false -> xls_collection_observation:width(maps:get(reductions, Interface))
            end,
            Tagged#{live_state => #{width => Width,
                port => iolist_to_binary(["_scheduler_", integer_to_list(Index), "_collection_debug_out"])}}
    end;
bank(Index, _Group, _Interface, _Placements, _Codebook) ->
    error({debug_requires_state_ram, Index}).

%% Adds reduction progress fields without exposing accumulator payloads.
-spec with_reduction(none | map(), xls_machine_layout:layout(), map()) -> map().
with_reduction(none, _Layout, Bank) -> Bank;
with_reduction(Reduction = #{sites := Sites}, MachineLayout, Bank) ->
    #{offset := Start} = xls_machine_layout:field(MachineLayout, reduction),
    Layout = xls_statem_reduction_ir:packed_layout(Reduction),
    Names = xls_statem_reduction_ir:observation_fields(Reduction),
    {Width, Fields} = lists:foldl(fun(Name, {Offset, Acc}) ->
        #{offset := Source, width := Bits} = maps:get(Name, Layout),
        {Offset + Bits, Acc#{Name => #{offset => Start + Source, width => Bits,
            observation_offset => 56 + Offset}}}
    end, {0, #{}}, Names),
    Bank#{reduction => #{width => Width, fields => Fields,
        sites => [maps:with([id, phase, name, population], Site) || Site <- Sites]}}.

%% Converts projection metadata into JSON-compatible values and keys.
-spec json_value(atom() | binary() | [any()] | number() | map()) -> 'false' | 'null' | 'true' | binary() | ['false' | 'null' | 'true' | binary() | [any()] | number() | map()] | number() | map().
json_value(Term) -> json:decode(iolist_to_binary(json:encode(Term))).
