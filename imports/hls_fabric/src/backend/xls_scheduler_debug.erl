-module(xls_scheduler_debug).
-moduledoc "Compiler-owned projections of committed actor state and scheduler metadata.".
-export([projection/3, projection/4, validate/3]).

%% Emit beside the RTL generated from this exact plan. The instrumentation tool
%% checks RAM interfaces and fingerprints this document with the RTL sources.
%% Artifacts are the exact actor DSLX files passed to XLS, indexed by module.
%% Keys are opaque hashes of logical Erlang IDs; the host never interns atoms
%% or decodes external Erlang terms supplied by a device or manifest.
-doc "Builds the physical actor observation map from matching topology and generated artifacts.".
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => iodata()}) -> map().
projection(Plan, Specs, Artifacts) ->
    projection(Plan, Specs, Artifacts, #{}).

-doc "Builds the physical actor observation map from matching topology and generated artifacts.".
-spec projection(hls_topology:plan(), hls_scheduler_plan:spec(),
    #{module() => iodata()}, #{mailbox_debug => boolean(), direct_actor_debug => boolean(), direct_collections => #{module() => exclusive_epoch},
        frame_payload_words => hls_frame_layout:words()}) -> map().
projection(Plan, Specs, Artifacts, Options) ->
    build(Plan, Specs, Options, fun(Module, Origins) ->
        xls_failure_sites:from_artifact(Origins, maps:get(Module, Artifacts))
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
    Placements = hls_scheduler_plan:placements(
        hls_scheduler_plan:normalize(Plan, Specs, hls_frame_layout:new(Words))),
    Direct = xls_actor_observation:bindings(Plan, Placements),
    Policies = maps:from_list([{M, exclusive_epoch} || #{module := M} <- Direct,
        B <- maps:get(<<"direct">>, Projection, []), maps:get(<<"module">>, B) =:= atom_to_binary(M),
        maps:get(<<"early_collection">>, maps:get(<<"reduction">>, B, #{}), false)]),
    Options = #{mailbox_debug => MailboxDebug, direct_actor_debug => maps:is_key(<<"direct">>, Projection),
        direct_collections => Policies, frame_payload_words => Words},
    Expected = build(Plan, Specs, Options, fun(Module, Origins) ->
        Values = maps:from_keys(maps:values(maps:get(atom_to_binary(Module), ByModule, #{})), true),
        xls_failure_sites:number([O || O <- Origins, is_map_key(json_value(O), Values)])
    end),
    case Projection =:= Expected of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end;
validate(_Plan, _Specs, _Projection) -> error(actor_projection_mismatch).

%% Combines observation banks and artifact fingerprints into a deterministic projection.
-spec build(map(),map(),map(),fun((term(),term()) -> [map()])) -> 'false' | 'null' | 'true' | binary() | ['false' | 'null' | 'true' | binary() | [any()] | number() | map()] | number() | map().
build(Plan, Specs, Options, Codebook) ->
    MailboxDebug = xls_scheduler_observation:enabled(Options),
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
    Scheduler = #{groups := Groups} = hls_scheduler_plan:normalize(Plan, Specs, Layout),
    Placements = hls_scheduler_plan:placements(Scheduler),
    Direct = case xls_actor_observation:enabled(Options) of
        true -> xls_actor_observation:bindings(Plan, Placements);
        false -> []
    end,
    Interfaces = hls_actor_interface:from_modules(lists:usort(
        [M || #{module := M} <- Groups ++ Direct])),
    Codebooks = maps:map(fun(Module, #{failure_origins := Origins}) ->
        Codebook(Module, Origins)
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
bank(Index, #{module := Module, slot_count := Slots, state := #{width := DataWidth},
        reduction_storage_width := ReductionWidth, state_storage := block_ram} = Group,
        Interface = #{phases := Phases}, Placements, Sites) ->
    Layout = xls_shared_codegen:shared_machine_layout(
        maps:get(physical_data_width, Group, DataWidth), ReductionWidth,
        maps:get(gather_storage_width, Group, 0)),
    Fields = maps:with([phase, enter_pending, failure], Layout),
    Entries = lists:keysort(1, [{Slot, #{key => xls_actor_debug:actor_key(Id), slot => Slot,
        name => iolist_to_binary(io_lib:format("~p", [Id]))}} ||
        {Id, #{index := I, slot := Slot}} <- maps:to_list(Placements), I =:= Index]),
    Bank = #{index => Index, ram => iolist_to_binary(["scheduler_", integer_to_list(Index), "_state"]),
        slots => Slots, width => maps:get(width, Layout) + maps:get(continuation_width, Group, 0) + maps:get(reply_storage_width, Group, 0), fields => Fields,
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
-spec with_reduction('none' | map(),map(),map()) -> map().
with_reduction(none, _Layout, Bank) -> Bank;
with_reduction(Reduction = #{sites := Sites}, #{reduction := #{offset := Start}}, Bank) ->
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
