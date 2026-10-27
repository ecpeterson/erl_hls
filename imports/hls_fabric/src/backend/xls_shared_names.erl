-module(xls_shared_names).
-moduledoc false.
-export([validate/1]).

-doc "Rejects actor declarations that collide with the shared backend's generated namespace.".
-spec validate(map()) -> ok.
validate(#{data_name := Data, message_names := Messages,
        imports := Imports, reductions := Reductions} = Spec) ->
    Accumulator = case Reductions of
        none -> [];
        #{accumulator := #{name := Name}} -> [Name]
    end,
    Elements = case maps:get(gathers, Spec, none) of
        none -> [];
        #{sites := Sites} -> [N || #{element := #{name := N}} <- Sites]
    end,
    Symbols = lists:append([[{xls_names:record_type(Name), record_type, Name},
        {xls_names:record_codec(Name) ++ "_from_bits", record_unpacker, Name},
        {"bits_from_" ++ xls_names:record_codec(Name), record_packer, Name}]
        || Name <- [Data | Messages] ++ Accumulator ++ Elements]) ++
        [{xls_names:import_alias(Module), import, Module} || Module <- Imports],
    Reserved = reserved(),
    lists:foreach(fun({Symbol, Kind, Origin}) ->
        case lists:member(Symbol, Reserved) of
            false -> ok;
            true -> error({xls_name_collision, module, Symbol,
                #{kind => generated, name => Symbol}, #{kind => Kind, name => Origin}})
        end
    end, Symbols).

%% Dedicated/common names are checked by the public lowerer. Only backend-owned
%% declarations belong here; adding a new one must extend the collision witness.
-spec reserved() -> [string()].
reserved() ->
    ["SharedOperands", "IndexedOwnedInput", "indexed_owned_mask", "indexed_capture_retirement", "indexed_capture_result", "indexed_write_data",
     "indexed_check_owned", "indexed_capture_input", "indexed_retire_owned", "indexed_refresh",
     "indexed_prepare_mask", "indexed_prepared_finish", "indexed_preparation_source",
     "indexed_prepared_in_flight", "indexed_prepared_ticket",
     "indexed_retire_context", "shared_write_mask", "ordinary_selection_source",
     "direct_collection_finish", "direct_collection_execute",
     "direct_collection_command", "direct_collection_advance",
     "DirectCollectionGrant", "direct_collection_next_grant", "STARTUP_BITS",
     "PUBLICATION_CAPACITY", "PublicationPatch", "publication_patch", "publication_frame", "MachineBits", "MachineRow", "machine_row_from_bits", "bits_from_machine_row", "MachineRamReadReq", "MachineRamReadResp",
     "MachineRamWriteReq", "MachineRamWriteResp", "MailboxRamReadReq",
     "MailboxRamReadResp", "MailboxRamWriteReq", "MailboxRamWriteResp",
     "ScheduledRequest", "ScheduledEffects", "SharedStep", "SharedExecutorRequest",
     "SharedExecutorResult", "SharedPhase", "SharedState", "SharedExecutor",
     "SharedService", "SharedLoader", "SharedRequestStage", "SharedDispatchTicket", "ReductionAggregate", "ReductionAggregateRequest",
     "ACTOR_COUNT", "PRODUCER_COUNT", "STARTUP_COUNT", "INSTANCE_ID",
     "machine_from_bits", "bits_from_machine", "reduction_state_from_bits",
     "bits_from_reduction_state", "shared_configuration",
     "shared_data_from_bits", "shared_bits_from_data", "CollectionObservation",
     "collection_machine_bits", "collection_try", "collection_retire", "collection_admit",
     "collection_commit", "collection_observation", "DirectCollection", "DirectCollectionStep",
     "DirectCollectionState", "CollectionService", "direct_collection_step", "direct_collection_machine",
     "collection_reserved", "collection_frame_valid", "collection_expected", "collection_count",
     "collection_push", "collection_open", "CollectionControl", "CollectionBank",
     "collection_control", "collection_accepts", "collection_fold", "collection_resolve",
     "collection_grant", "collection_selected_input", "collection_select", "collection_select_ordinary", "collection_issue", "CollectionInput",
     "collection_decode", "collection_push_input", "collection_accepts_input",
     "collection_capture_inputs", "GatherRamReadReq", "GatherRamReadResp",
     "GatherRamWriteReq", "GatherRamWriteResp", "IndexedBanks", "IndexedLease",
     "IndexedContext", "IndexedInput", "IndexedEligibility", "IndexedTicket", "IndexedAdmission",
     "INDEXED_CAPACITY", "INDEXED_ELEMENT_BITS", "INDEXED_SITE", "gather_ready_selection",
     "shared_machine_complete_gather", "shared_machine_gather_dispatch",
     "indexed_reserved", "indexed_frame_valid", "indexed_stable", "indexed_transport_contribution",
     "indexed_dispatch", "indexed_selected_frame", "indexed_failure", "indexed_decode", "indexed_classify", "indexed_find", "indexed_lease",
     "indexed_retained", "indexed_can_accept", "indexed_input_fault", "indexed_push",
     "indexed_open", "indexed_revalidate", "indexed_control", "indexed_ticket", "indexed_ready",
     "indexed_completion_descriptor", "indexed_ticket_with_descriptor", "indexed_selected_ticket",
     "indexed_admission_ready",
     "indexed_resolve", "indexed_retire", "indexed_ordinary_state",
     "scalar_collection_observation", "indexed_observation_progress", "indexed_grant", "indexed_select", "indexed_admit", "indexed_commit", "indexed_issue"].
