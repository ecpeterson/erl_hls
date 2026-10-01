-module(xls_shared_names).
-moduledoc false.
-export([validate/1]).

-doc "Rejects actor declarations that collide with the shared backend's generated namespace.".
-spec validate(map()) -> ok.
validate(#{data_name := Data, message_names := Messages,
        imports := Imports, reductions := Reductions}) ->
    Accumulator = case Reductions of
        none -> [];
        #{accumulator := #{name := Name}} -> [Name]
    end,
    Symbols = lists:append([[{xls_names:record_type(Name), record_type, Name},
        {xls_names:record_codec(Name) ++ "_from_bits", record_unpacker, Name},
        {"bits_from_" ++ xls_names:record_codec(Name), record_packer, Name}]
        || Name <- [Data | Messages] ++ Accumulator]) ++
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
    ["MachineBits", "MachineRamReadReq", "MachineRamReadResp",
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
     "collection_select", "collection_select_ordinary", "collection_issue", "CollectionInput",
     "collection_decode", "collection_push_input", "collection_accepts_input",
     "collection_capture_inputs"].
