-module(xls_shared_topology_family_dslx).
-moduledoc "Adds shared placement to the common regular-family routing graph.".
-export([lower/2]).

-doc "Checks family placement and reduction requirements, retaining compiler family annotations and explicit scheduler bindings. Compact shared ownership is completed by xls_topology_scheduler_plan before rendering.".
-spec lower(hls_topology:plan(), xls_shared_topology_profile:profile()) -> map().
lower(Plan, Profile0) ->
    Profile = #{scheduler_groups := Groups, reduction_placements := Placements,
        effect_window_partition := WindowPartition, mailbox_debug := MailboxDebug,
        frame_payload_words := PayloadWords} =
        xls_shared_topology_profile:normalize(Profile0),
    SchedulerPlan = hls_scheduler_plan:normalize(Plan, Groups, hls_frame_layout:new(PayloadWords)),
    case SchedulerPlan of
        #{groups := [_ | _], direct_members := [_ | _]} -> error(mixed_topology_requires_materialized_backend);
        _ -> ok
    end,
    Schedulers = annotate_schedulers(maps:get(groups, SchedulerPlan)),
    case lists:any(fun(G) -> maps:get(admission_reductions, G, false) =/= false orelse maps:get(gather_collection, G, false) end, Schedulers) of
        true -> error(admission_reductions_require_materialized_topology); false -> ok end,
    case {MailboxDebug, Schedulers} of
        {true, []} -> error(mailbox_debug_requires_shared_schedulers);
        _ -> ok
    end,
    Base = #{families := Families} = xls_topology_family_dslx:lower(Plan,
        maps:with([name, channel_depth, actor_egress_depth, direct_actor_debug, frame_payload_words], Profile)),
    ReductionPlan = hls_reduction_plan:normalize(Plan, SchedulerPlan, Placements),
    Bindings = scheduler_bindings(Schedulers),
    Requirements = maps:merge(maps:from_list([{Module, #{shared_service => ordinary}} ||
        #{module := Module} <- Families]), hls_reduction_plan:artifact_requirements(ReductionPlan)),
    Base#{families := [with_scheduler_bindings(F, Bindings) || F <- Families],
        schedulers => Schedulers, mailbox_debug => MailboxDebug,
        effect_window_partition => WindowPartition, reduction_plan => ReductionPlan,
        artifact_requirements := maps:map(fun(_, Requirement) ->
            WithLayout = Requirement#{frame_payload_words => maps:get(frame_payload_words, Profile)},
            WithMailbox = case MailboxDebug of true -> WithLayout#{mailbox_debug => true}; false -> WithLayout end,
            case maps:get(direct_actor_debug, Profile) andalso Schedulers =:= [] of
                true -> WithMailbox#{direct_actor_debug => true}; false -> WithMailbox
            end
        end, Requirements)}.

%% Attaches family ownership and RAM bindings to the logical graph.
-spec annotate_schedulers([map()]) -> [map()].
annotate_schedulers(Groups) ->
    [annotate_scheduler(Index, Group)
        || {Index, Group} <- lists:enumerate(0, Groups)].

%% Assigns actor addresses, producer lanes and routed destinations to one group.
-spec annotate_scheduler(integer(),map()) -> map().
annotate_scheduler(Index, Group = #{
    state_storage := block_ram,
    mailbox_storage := block_ram
}) ->
    Group#{
        index => Index,
        stem => ["scheduler_", integer_to_list(Index)],
        module_name => xls_shared_topology_profile:identifier(
            maps:get(module, Group), scheduler_module)
    };
annotate_scheduler(_Index, #{
    id := Id,
    state_storage := State,
    mailbox_storage := Mailbox
}) ->
    error({scheduler_storage, Id, State, Mailbox}).

%% Lists state and mailbox RAM interfaces required by the shared groups.
-spec scheduler_bindings([map()]) -> map().
scheduler_bindings(Schedulers) ->
    lists:foldl(
        fun({Id, Binding}, Acc) ->
            maps:update_with(Id, fun(Existing) -> Existing ++ [Binding] end,
                [Binding], Acc)
        end,
        #{},
        [{Id, #{
            group => Group,
            base_slot => BaseSlot,
            instances => Instances
        }}
        || #{index := Group, members := Members} <- Schedulers,
           #{kind := family, id := Id, base_slot := BaseSlot,
               instances := Instances} <- Members]
    ).

%% Includes the shared RAM interfaces in the generated top-level signature.
-spec with_scheduler_bindings(map(),map()) -> map().
with_scheduler_bindings(Family = #{id := Id}, Bindings) ->
    Family#{schedulers => maps:get(Id, Bindings, [])}.
