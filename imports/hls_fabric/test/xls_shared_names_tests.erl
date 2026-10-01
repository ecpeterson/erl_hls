-module(xls_shared_names_tests).
-include_lib("eunit/include/eunit.hrl").

%% Backend-only generated names must fail before DSLX parsing, including imports
%% and private accumulator records whose names are absent from public messages.
-spec backend_namespace_test() -> ok.
backend_namespace_test() ->
    Base = #{data_name => cell, message_names => [value], imports => [], reductions => none},
    ok = xls_shared_names:validate(Base),
    lists:foreach(fun(Name) ->
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_shared_names:validate(Base#{data_name := Name})),
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_shared_names:validate(Base#{reductions := #{accumulator => #{name => Name}}}))
    end, ['SharedState', 'SharedExecutor', 'SharedLoader', 'SharedRequestStage', 'SharedDispatchTicket',
         'ReductionAggregate', 'MachineBits', 'CollectionControl', 'CollectionBank', 'CollectionInput']),
    lists:foreach(fun(Alias) ->
        ?assertException(error, {xls_name_collision, module, _, _, _},
            xls_shared_names:validate(Base#{imports := [Alias]}))
    end, ['backend.SharedService', 'backend.collection_control', 'backend.collection_accepts',
          'backend.collection_fold', 'backend.collection_resolve', 'backend.collection_select',
          'backend.collection_select_ordinary', 'backend.collection_issue', 'backend.collection_decode',
          'backend.collection_push_input', 'backend.collection_accepts_input', 'backend.collection_capture_inputs']).
