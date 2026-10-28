-module(xls_activation_codegen).
-moduledoc """
Finalizes ordinary actor execution as a sealed DSLX artifact for hls_local_actor. Reuses compiler callback lowering and the common machine renderer without introducing scheduler RAM, actor selection or publication ownership.

The caller supplies mailbox ordering, state/effect storage and a clock owner. Failure references are finalized with the complete actor module; this layer chooses neither a RAM service nor an actor scheduler.
""".

%% Structured artifact and byte convenience output.
-export([artifact/1, emit/1]).
%% The public facade accepts only the compiler artifact and a checked instance-zero projection.
-type spec() :: xls_actor_codegen:spec().

-doc "Emits the ordinary source-derived activation semantics without a RAM owner, loader or topology. Accepts a closed actor artifact with an optional source-validated constant projection for instance zero; retained replies and physical service options are rejected. Callers must reserve state/effect storage and preserve mailbox order. This reference boundary does not establish a local protocol specialization.".
-spec emit(xls_actor_codegen:spec()) -> binary().
emit(Closed) -> xls_emitted:bytes(artifact(Closed)).

-doc "Renders checked ordinary activation semantics and retains its emitted failure codebook. Rejects collisions with generated backend names. The same closed-artifact and ownership constraints as emit/1 apply; enclosing protocol composition must preserve this metadata.".
-spec artifact(xls_actor_codegen:spec()) -> xls_emitted:artifact().
artifact(Closed) ->
    case
        maps:keys(Closed) --
            [
                source,
                failure_locations,
                imports,
                capacity,
                phases,
                frame_layout,
                message_names,
                message_words,
                output_names,
                max_entry_effects,
                data_name,
                data_width,
                record_declarations,
                helper_functions,
                init,
                entries,
                casts,
                continuations,
                retained_calls,
                internal_steps,
                reductions,
                gathers,
                state_projection
            ]
    of
        [] -> ok;
        Unknown -> error({local_execution_requires_closed_artifact, Unknown})
    end,
    Spec = Closed#{shared_service => ordinary},
    case maps:get(retained_calls, Spec) of
        none -> ok;
        _ -> error(local_execution_retained_calls_unsupported)
    end,
    case maps:find(state_projection, Spec) of
        {ok, #{rows := Rows}} ->
            case lists:usort([I || #{instance := I} <- Rows]) of
                [0] -> ok;
                _ -> error(local_execution_requires_instance_zero)
            end;
        error ->
            ok
    end,
    ok = xls_machine_names:validate(Spec),
    xls_actor_codegen:artifact(
        Spec,
        [],
        [
            xls_machine_codegen:state_type(Spec),
            xls_machine_codegen:step_type(),
            xls_machine_codegen:executor_types(Spec),
            xls_state_projection:functions(Spec),
            xls_machine_codegen:codec(Spec),
            xls_gather_codegen:helpers(Spec),
            xls_machine_codegen:step(Spec),
            xls_machine_codegen:execute(Spec),
            execution_ports(Spec)
        ]
    ).

%% Fill the ordinary activation API without selecting application-specific callbacks or storage.
-spec execution_ports(spec()) -> iodata().
execution_ports(Spec = #{reductions := Reduction, continuations := Events}) ->
    ReductionPending =
        case Reduction of
            none -> [];
            _ -> " || machine.reduction.status == ReductionStatus::COMPLETE"
        end,
    Pending = [
        "machine.enter_pending",
        case Events of
            [] -> [];
            _ -> " || machine.next_event != u8:0"
        end,
        case maps:get(gathers, Spec, none) of
            none -> [];
            _ -> " || machine.gather.progress.status == GatherStatus::COMPLETE"
        end,
        ReductionPending
    ],
    {Decode, Execute} =
        case maps:is_key(state_projection, Spec) of
            true -> {"machine_from_bits<u32:0>(raw, slot)", "shared_execute<u32:0>(request)"};
            false -> {"machine_from_bits(raw)", "shared_execute(request)"}
        end,
    Internal =
        case Reduction of
            none ->
                [];
            _ ->
                "internal: !machine.enter_pending && machine.reduction.status == ReductionStatus::COMPLETE,"
        end,
    Path = filename:join(code:priv_dir(hls_lowering), "xls/templates/local_execution.x.in"),
    {ok, Template} = file:read_file(Path),
    xls_template:render(Template, [
        {<<"@@DECODE@@">>, Decode},
        {<<"@@EXECUTE@@">>, Execute},
        {<<"@@PENDING@@">>, Pending},
        {<<"@@INTERNAL@@">>, Internal}
    ]).
