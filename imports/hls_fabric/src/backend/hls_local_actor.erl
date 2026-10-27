-module(hls_local_actor).
-moduledoc "Compiles ordinary local actor functions and a single-actor DSLX clock owner from source.".
-export([prepare/2, prepare/3, render/1, descriptor/1, compile/2, emit/2, write/2, write/3, manifest/1]).
-export_type([source/0, artifact/0, completion/0, descriptor/0, manifest/0]).

-doc "Checked ordinary source semantics before hardware rendering. The compiler program retains the source snapshot. Optional completion selects an owner ABI; inbox and import fields describe checked receiver wiring. Retain unchanged within the build, never accept a supplied map as compiled source.".
-type source() :: #{program := xls_actor_program:program(), source := file:filename(),
    context => hls_source:context(), completion => completion(), inbox => hls_protocol_inbox:metadata(), owner_import => owner_import()}.

%% Compiler-owned provenance is serialized for reporting, never read as a backend plan.
-type inventory_value() :: atom() | binary() | number() | [inventory_value()] |
    #{atom() | binary() => inventory_value()}.

%% Fixed scheduling promises describe this owner implementation, not application admission.
-type owner_contract() :: #{selected_head := reserved_until_head_done_or_reset,
    retirement := dispatched_directive_and_phase_boundary, publication := one_ordered_batch,
    action := registered_once_then_entry_retry, startup := one_masked_clock_for_source_initialization,
    schedule := one_stage_no_io_flops_always_enabled_channels}.

%% Static and emitted interfaces share fields; the latter requires a generated-byte identity.
-define(INTERFACE_FIELDS, completion := completion(), version := 1, stage := source_actor_and_owner,
    source := binary(), source_plan := #{atom() | binary() => inventory_value()},
    machine_layout := xls_shared_codegen:machine_layout(), continuation_bits := 0 | 8,
    machine_bits := pos_integer(), effect_payload_bits := pos_integer(), source_imports := [atom()],
    output_ports := [atom()], message_schemas := [atom()],
    completion_sites := [#{id := non_neg_integer(), phase := atom()}], phase_names := [atom()],
    function_ports := [atom()], clock_proc := local_owner_clock | local_inbox_clock,
    frame_layout := hls_frame_layout:layout(), build_profile := hls_build_profile:profile(), codegen_flags := [binary()],
    owner_contract := owner_contract(), action_result_fields := [atom()], action_obligations := [atom()],
    receipt_result_fields := [atom()], receipt_obligations := [atom()], step_result_fields := [atom()],
    handwritten_application_controller := false, source_semantics_reused := [atom()],
    physical_locality_established := false, excluded := [atom()],
    inbox => hls_protocol_inbox:metadata(), owner_import => none | owner_import()).

-doc "Source/owner interface metadata before the module's generated-byte identity. Imported receivers may retain their owner's hash; source_plan is compiler-owned JSON provenance, not a backend planning input.".
-type descriptor() :: #{?INTERFACE_FIELDS}.

-doc "The source/owner interface with its allocated failure codebook and hashes of rendered DSLX and selected frame configuration bytes.".
-type manifest() :: #{?INTERFACE_FIELDS, dslx_sha256 := binary(), frame_config_sha256 := binary(), failure_sites := [xls_failure_sites:site()]}.

%% Planning binds the import path; emission additionally binds the rendered owner bytes.
-type owner_import() :: #{file := binary(), dslx_sha256 => binary()}.

-doc "Local scalar completion or a source-compatible shared group selected by the arithmetic planner.".
-type completion() :: #{mode := local} | #{mode := shared, group := non_neg_integer()}.

-doc "One fresh ordinary compilation, its activation/receipt/action functions and clocked owner, rendered after optional shared-completion selection and bound to its checked inbox by hls_protocol_inbox:attach/2. The opaque compiler program owns the complete source snapshot; retain it with the DSLX. Supplied or edited artifacts are outside this trusted build API. Network receivers may import an owner artifact in the same bundle; owner_import binds that relative file and its DSLX hash.".
-type artifact() :: #{program := xls_actor_program:program(),
    emitted := xls_emitted:artifact(), source := file:filename(), context => hls_source:context(),
    inbox => hls_protocol_inbox:metadata(), completion => completion(), owner_import => owner_import()}.

-doc "Compiles all source callback families once with ordinary failure and collection semantics and a clocked DSLX owner. Rejects retained synchronous calls; no application names select behavior.".
-spec compile(file:filename(), [hls_source:option()] | hls_source:context()) -> artifact().
compile(Source, Options) -> render(prepare(Source, Options)).

-doc "Lowers one source snapshot and rejects retained synchronous calls before any owner or port DSLX is rendered. The returned source is reusable across placements; source constructors and compiler codecs remain trusted build code.".
-spec prepare(file:filename(), [hls_source:option()] | hls_source:context()) -> source().
prepare(Source, Options) -> prepare(Source, Options, hls_frame_layout:default()).

-doc "Lowers one source snapshot with the selected canonical frame capacity. The layout belongs to this compiler program and every enclosing receiver; source validation rejects messages beyond that capacity before rendering.".
-spec prepare(file:filename(), [hls_source:option()] | hls_source:context(), hls_frame_layout:layout()) -> source().
prepare(Source, Options, FrameLayout) ->
    Program = xls_actor_program:from_file(Source, Options, FrameLayout),
    Spec = xls_actor_program:spec(Program),
    case maps:get(retained_calls, Spec) of
        none -> ok;
        _ -> hls_diagnostic:raise(source, local_execution_retained_calls_unsupported,
            <<"The local protocol owner does not support retained call replies.">>,
            #{source => unicode:characters_to_binary(Source), capability => retained_calls})
    end,
    #{source => Source, program => Program}.

-doc "Renders the checked source's ordinary functions and selected clock-owner ABI without rereading source. Templates are read here. Inbox attachment and imported-owner wiring belong to the enclosing transport emission.".
-spec render(source()) -> artifact().
render(Source = #{program := Program}) ->
    Spec = xls_actor_program:spec(Program),
    Mode = maps:get(mode, maps:get(completion, Source, #{mode => local})),
    Execution = xls_shared_codegen:execution_artifact(Spec),
    Source#{emitted => xls_emitted:with_bytes(Execution,
        iolist_to_binary([xls_emitted:bytes(Execution), hls_local_protocol:ports(Spec, Mode)]))}.

-doc "Returns an existing artifact's DSLX, JSON provenance and selected frame_config.x beside the relative source filename, without recompilation or output I/O. The enclosing writer validates paths; multiple actors in one directory must share the same configuration.".
-spec emit(artifact(), string()) -> hls_generated_files:files().
emit(Artifact = #{emitted := Emitted}, RelativeFilename) ->
    Bytes = xls_emitted:bytes(Emitted),
    Manifest = #{frame_layout := Layout} = manifest(Artifact),
    ConfigName = case filename:dirname(RelativeFilename) of
        "." -> "frame_config.x";
        Directory -> filename:join(Directory, "frame_config.x")
    end,
    case RelativeFilename of
        ConfigName -> error({local_actor_reserved_output, RelativeFilename});
        _ -> ok
    end,
    #{RelativeFilename => Bytes, RelativeFilename ++ ".json" => json:encode(Manifest),
        ConfigName => hls_frame_layout:config_dslx(Layout)}.

-doc "Writes a fresh source-derived DSLX module, provenance and selected frame_config.x. Refuses existing source/manifest files and an incompatible shared frame configuration; generated code contains no application-specific RTL controller.".
-spec write(file:filename(), [hls_source:option()] | hls_source:context(), file:filename()) -> manifest().
write(Source, Options, Output) ->
    write(compile(Source, Options), Output).

-doc "Writes an artifact returned by render/1 without recompiling. Output and its .json sidecar must be absent; an existing sibling frame_config.x is accepted only if its bytes match. Conflicting capacity rejects before writing the source or sidecar; partial I/O failures are retained. This trusted in-process API does not validate saved or supplied artifacts.".
-spec write(artifact(), file:filename()) -> manifest().
write(Artifact, Output) ->
    lists:foreach(fun fresh/1, [Output, Output ++ ".json"]),
    Manifest = manifest(Artifact),
    Filename = filename:basename(Output), Sidecar = Filename ++ ".json",
    #{Filename := Bytes, Sidecar := Json, "frame_config.x" := Config} = emit(Artifact, Filename),
    ok = shared_frame_config(filename:join(filename:dirname(Output), "frame_config.x"), iolist_to_binary(Config)),
    ok = file:write_file(Output, Bytes, [exclusive]),
    ok = file:write_file(Output ++ ".json", Json, [exclusive]),
    Manifest.

%% Exclusive creation preserves an existing layout, including when two writers reach the directory together.
-spec shared_frame_config(file:filename(), binary()) -> ok.
shared_frame_config(Path, Bytes) ->
    case file:write_file(Path, Bytes, [exclusive]) of
        ok -> ok;
        {error, eexist} ->
            case file:read_file(Path) of
                {ok, Bytes} -> ok;
                {ok, _} -> error({local_actor_frame_config_mismatch, Path});
                {error, Reason} -> error({local_actor_output, Path, Reason})
            end;
        {error, Reason} -> error({local_actor_output, Path, Reason})
    end.

%% Refuse either existing output before writing its companion; exclusive writes also guard races.
-spec fresh(file:filename()) -> ok.
fresh(Path) ->
    case file:read_link_info(Path) of
        {error, enoent} -> ok;
        {ok, _} -> error({local_actor_output_exists, Path});
        {error, Reason} -> error({local_actor_output, Path, Reason})
    end.

-doc "Reports activation/receipt/action layouts, caller obligations and source/DSLX identities. Includes the clocked owner, completion mode and optional source-bound inbox contract; no network admission or timing benefit is established.".
-spec manifest(artifact()) -> manifest().
manifest(Artifact = #{emitted := Emitted, program := Program}) ->
    Bytes = xls_emitted:bytes(Emitted),
    #{failure_locations := Locations} = xls_actor_program:spec(Program),
    Descriptor = #{frame_layout := Layout} = descriptor(Artifact),
    Descriptor#{failure_sites => xls_emitted:sites(Emitted, Locations), dslx_sha256 => hls_generated_files:hash(Bytes),
        frame_config_sha256 => hls_generated_files:hash(hls_frame_layout:config_dslx(Layout))}.

-doc "Returns source layouts, port obligations and optional checked inbox metadata before rendering. Prepared sources contain no generated-byte hashes; an already rendered input retains its import identity. manifest/1 adds the owner module and frame-configuration identities. A source snapshot alone does not establish network admission or physical locality.".
-spec descriptor(source() | artifact()) -> descriptor().
descriptor(Artifact = #{program := Program, source := Source}) ->
    Spec = xls_actor_program:spec(Program),
    Plan = xls_actor_program:plan(Program),
    #{entries := Entries, reductions := Reductions,
        gathers := Gathers, continuations := Events} = Spec,
    DataWidth = xls_state_projection:width(Spec),
    ReductionWidth = xls_statem_reduction_codegen:private_width(Reductions),
    GatherWidth = xls_statem_gather_codegen:storage_width(Gathers),
    Layout = xls_shared_codegen:shared_machine_layout(DataWidth, ReductionWidth, GatherWidth),
    EventWidth = case Events of [] -> 0; _ -> 8 end,
    PayloadWidth = lists:max([1 | [xls_entry_storage:width(Storage)
        || #{layouts := Layouts} <- Entries, #{storage := Storage} <- Layouts]]),
    FrameLayout = maps:get(frame_layout, Spec),
    Profile = hls_build_profile:owner(FrameLayout),
    Base = #{frame_layout => FrameLayout, build_profile => Profile, codegen_flags => hls_build_profile:flags(Profile, sampled_clock),
        completion => maps:get(completion, Artifact, #{mode => local}), version => 1, stage => source_actor_and_owner, source => unicode:characters_to_binary(Source),
        source_plan => safe(xls_statem_plan:manifest(Plan)),
        machine_layout => Layout, continuation_bits => EventWidth,
        machine_bits => maps:get(width, Layout) + EventWidth,
        effect_payload_bits => PayloadWidth,
        source_imports => maps:get(imports, Spec),
        output_ports => maps:get(output_names, Spec),
        message_schemas => maps:get(message_names, Spec),
        completion_sites => case Gathers of none -> []; #{sites := Sites} ->
            [maps:with([id,phase], S) || S <- Sites] end,
        phase_names => maps:get(phases, Spec),
        function_ports => [local_initial, local_pending, local_pending_at, local_step,
            local_step_at, local_effect, local_observe, local_cycle, local_protocol_at, local_slow_step_at,
            local_action_at, local_enter_at, local_owner_initial, local_owner_tick],
        clock_proc => local_owner_clock,
        owner_contract => #{selected_head => reserved_until_head_done_or_reset,
            retirement => dispatched_directive_and_phase_boundary,
            publication => one_ordered_batch,
            action => registered_once_then_entry_retry,
            startup => one_masked_clock_for_source_initialization,
            schedule => one_stage_no_io_flops_always_enabled_channels},
        action_result_fields => [private_machine, dispatched, directive, phase_boundary],
        action_obligations => [intercept_handled_receipts, suppress_receive_while_pending,
            retain_action_and_mailbox_head, retain_actor_slot, reserve_publication,
            retry_blocked_publication_without_redispatch],
        receipt_result_fields => [handled, deferred_completion, private_machine, dispatched, directive],
        receipt_obligations => [intercept_handled_receipts, suppress_receive_while_pending,
            retain_final_gather_head, reserve_effects_for_completion],
        step_result_fields => [machine, effect_payload, effect_layout, effect_count,
            effects_valid, dispatched, directive, phase_boundary, egress_blocked],
        handwritten_application_controller => false,
        source_semantics_reused => [init, entry, cast, continuation, reduction,
            gather, failure_priority, ordered_effects],
        physical_locality_established => false,
        excluded => [retained_calls, protocol_fusion, network_runtime,
            functional_equivalence_proof, native_measurement]},
    case maps:find(inbox, Artifact) of
        error -> Base;
        {ok, Inbox} -> Base#{clock_proc := local_inbox_clock, inbox => Inbox,
            owner_import => maps:get(owner_import, Artifact, none),
            function_ports := maps:get(function_ports, Base) ++
                [local_inbox_initial, local_inbox_eligible, local_inbox_tick,
                 local_inbox_batch, local_inbox_batch_tick]}
    end.

%% JSON cannot encode tuple keys or arbitrary tuples; this preserves inventories
%% as nested values and never substitutes for the in-memory source-bound plan.
-spec safe(term()) -> term().
safe(Map) when is_map(Map) -> maps:from_list([{safe_key(K), safe(V)} || {K,V} <- maps:to_list(Map)]);
safe(Tuple) when is_tuple(Tuple) -> [safe(V) || V <- tuple_to_list(Tuple)];
safe(List) when is_list(List) -> [safe(V) || V <- List];
safe(Value) -> Value.

%% Source inventories use atom keys; unusual composite keys retain an explicit term spelling.
-spec safe_key(term()) -> atom() | binary().
safe_key(Key) when is_atom(Key); is_binary(Key) -> Key;
safe_key(Key) -> iolist_to_binary(io_lib:format("~p", [Key])).
