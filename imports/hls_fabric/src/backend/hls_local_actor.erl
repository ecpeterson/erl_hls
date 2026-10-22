-module(hls_local_actor).
-moduledoc "Compiles ordinary local actor functions and a single-actor DSLX clock owner from source.".
-export([compile/2, write/2, write/3, manifest/1]).
-export_type([artifact/0]).

-doc "One fresh ordinary compilation, its activation/receipt/action functions and its clocked owner. Consumers must retain the spec, plan and DSLX together; supplied or edited artifacts are outside this trusted build API.".
-type artifact() :: #{spec := xls_actor_codegen:spec(), plan := xls_statem_plan:plan(),
    dslx := binary(), source := file:filename()}.

-doc "Compiles all source callback families once with ordinary failure and collection semantics and a clocked DSLX owner. Rejects retained synchronous calls; no application names select behavior.".
-spec compile(file:filename(), [hls_source:option()] | hls_source:context()) -> artifact().
compile(Source, Options) ->
    {Spec, Plan} = xls_statem_plan:from_file(Source, Options),
    case maps:get(retained_calls, Spec) of
        none -> ok;
        _ -> error(local_execution_retained_calls_unsupported)
    end,
    #{source => Source, spec => Spec, plan => Plan,
        dslx => iolist_to_binary([xls_shared_codegen:execution(Spec), hls_local_protocol:ports(Spec)])}.

-doc "Writes a fresh source-derived DSLX module and provenance manifest. Refuses existing files; generated code contains no application-specific RTL controller.".
-spec write(file:filename(), [hls_source:option()] | hls_source:context(), file:filename()) -> map().
write(Source, Options, Output) ->
    write(compile(Source, Options), Output).

-doc "Writes an artifact returned by compile/2 without recompiling or selecting callbacks. Output and its .json sidecar must both be absent; partial I/O failures are retained. This is a trusted in-process build API, not validation of a saved or supplied artifact.".
-spec write(artifact(), file:filename()) -> map().
write(Artifact = #{dslx := Bytes}, Output) ->
    lists:foreach(fun fresh/1, [Output, Output ++ ".json"]),
    Manifest = manifest(Artifact),
    ok = file:write_file(Output, Bytes, [exclusive]),
    ok = file:write_file(Output ++ ".json", json:encode(Manifest), [exclusive]),
    Manifest.

%% Refuse either existing output before writing its companion; exclusive writes also guard races.
-spec fresh(file:filename()) -> ok.
fresh(Path) ->
    case file:read_link_info(Path) of
        {error, enoent} -> ok;
        {ok, _} -> error({local_actor_output_exists, Path});
        {error, Reason} -> error({local_actor_output, Path, Reason})
    end.

-doc "Reports activation/receipt/action layouts, caller obligations and source/DSLX identities. Includes the clocked owner contract; no network admission or timing benefit is established.".
-spec manifest(artifact()) -> map().
manifest(#{spec := Spec, plan := Plan, dslx := Bytes, source := Source}) ->
    #{entries := Entries, reductions := Reductions,
        gathers := Gathers, continuations := Events} = Spec,
    DataWidth = xls_state_projection:width(Spec),
    ReductionWidth = xls_statem_reduction_codegen:private_width(Reductions),
    GatherWidth = xls_statem_gather_codegen:storage_width(Gathers),
    Layout = xls_shared_codegen:shared_machine_layout(DataWidth, ReductionWidth, GatherWidth),
    EventWidth = case Events of [] -> 0; _ -> 8 end,
    PayloadWidth = lists:max([1 | [xls_entry_storage:width(Storage)
        || #{layouts := Layouts} <- Entries, #{storage := Storage} <- Layouts]]),
    #{version => 1, stage => source_actor_and_owner, source => unicode:characters_to_binary(Source),
        source_plan => safe(xls_statem_plan:manifest(Plan)),
        dslx_sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase),
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
            functional_equivalence_proof, native_measurement]}.

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
