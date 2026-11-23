-module(xls_machine_names_tests).
-include_lib("eunit/include/eunit.hrl").

%% Backend-only generated names must fail before DSLX parsing, including imports
%% and private accumulator records whose names are absent from public messages.
-spec backend_namespace_test() -> ok.
backend_namespace_test() ->
    Base = #{data_name => cell, message_names => [value], imports => [], reductions => none},
    ok = xls_machine_names:validate(Base),
    lists:foreach(fun(Name) ->
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_machine_names:validate(Base#{data_name := Name})),
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_machine_names:validate(Base#{reductions := #{accumulator => #{name => Name}}}))
    end, ['SharedOperands', 'IndexedOwnedInput', 'PublicationPatch', 'SharedState', 'SharedExecutor', 'SharedLoader', 'SharedRequestStage', 'SharedDispatchTicket',
         'ReductionAggregate', 'MachineBits', 'MachineRow', 'CollectionControl', 'CollectionBank', 'CollectionInput', 'DirectCollectionGrant', 'IndexedContext', 'GatherRamReadReq']),
    lists:foreach(fun(Alias) ->
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_machine_names:validate(Base#{imports := [Alias]}))
    end, ['backend.machine_row_from_bits', 'backend.bits_from_machine_row', 'backend.indexed_prepare_mask', 'backend.indexed_prepared_finish',
          'backend.indexed_preparation_source', 'backend.indexed_prepared_in_flight',
          'backend.indexed_prepared_ticket', 'backend.indexed_owned_mask', 'backend.indexed_capture_result', 'backend.indexed_write_data', 'backend.indexed_capture_retirement',
          'backend.indexed_check_owned', 'backend.indexed_capture_input', 'backend.indexed_retire_owned',
          'backend.indexed_refresh', 'backend.indexed_retire_context', 'backend.shared_write_mask',
          'backend.ordinary_selection_source', 'backend.direct_collection_finish', 'backend.direct_collection_execute',
          'backend.direct_collection_command', 'backend.direct_collection_advance',
          'backend.direct_collection_next_grant',
          'backend.publication_patch', 'backend.publication_frame', 'backend.SharedService', 'backend.collection_control', 'backend.collection_accepts',
          'backend.collection_fold', 'backend.collection_resolve', 'backend.collection_select',
          'backend.collection_select_ordinary', 'backend.collection_issue', 'backend.collection_decode',
          'backend.collection_push_input', 'backend.collection_accepts_input', 'backend.collection_capture_inputs',
          'backend.indexed_completion_descriptor', 'backend.indexed_ticket_with_descriptor',
          'backend.indexed_selected_ticket', 'backend.indexed_admission_ready']).

%% A private element type cannot shadow its physical store or completion envelope.
-spec gather_element_namespace_test() -> ok.
gather_element_namespace_test() ->
    Base = #{data_name => cell, message_names => [], imports => [], reductions => none,
        gathers => #{sites => [#{element => #{name => 'IndexedLease'}}]}},
    ?assertException(error, {xls_name_collision, module, "IndexedLease", _, _},
        xls_machine_names:validate(Base)).
