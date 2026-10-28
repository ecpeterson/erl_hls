-module(xls_collection_codegen_tests).
-include_lib("eunit/include/eunit.hrl").

%% Mailbox admission uses only its supplied reservation-filtered source in both policies.
-spec ordinary_selection_keeps_source_and_result_bindings_test() -> ok.
ordinary_selection_keeps_source_and_result_bindings_test() ->
    lists:foreach(fun(Mode) ->
        Text = selection(#{admission_reductions => Mode}),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"let next_mail = mailbox::select_admission(">>)),
        lists:foreach(fun(Field) ->
            ?assertNotEqual(nomatch, binary:match(Text,
                <<"masked_state.", Field/binary>>))
        end, [<<"occupied">>, <<"used">>, <<"admission_cursor">>,
            <<"pending">>, <<"pending_valid">>]),
        ?assertEqual(nomatch, binary:match(Text, <<"collector_state">>)),
        ?assertEqual(nomatch, binary:match(Text, <<"collection_intent">>))
    end, [false, true]).

%% Indexed preparation filters ordinary mail without introducing a collector selection.
-spec indexed_selection_projects_only_ordinary_admission_test() -> ok.
indexed_selection_projects_only_ordinary_admission_test() ->
    lists:foreach(fun(Mode) ->
        Text = selection(#{gather_collection => true, admission_reductions => Mode}),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"let ordinary_state = indexed_ordinary_state(masked_state);">>)),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"let next_mail = mailbox::select_admission(\n          ordinary_state.occupied">>)),
        ?assertEqual(nomatch, binary:match(Text, <<"masked_state.pending">>)),
        ?assertEqual(nomatch, binary:match(Text, <<"collector_state">>))
    end, [false, true]).

%% Exclusive contributions always select from independent ownership, even with indexed mail.
-spec exclusive_selection_preserves_independent_collector_source_test() -> ok.
exclusive_selection_preserves_independent_collector_source_test() ->
    lists:foreach(fun({Indexed, OrdinarySource}) ->
        Text = selection(#{gather_collection => Indexed,
            admission_reductions => exclusive_epoch}),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"let next_mail = collection_select_ordinary(", OrdinarySource/binary, ");">>)),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"let collection_intent = collection_select(collector_state);">>)),
        ?assertEqual(nomatch, binary:match(Text, <<"collection_select(masked_state)">>)),
        ?assertEqual(nomatch, binary:match(Text, <<"mailbox::select_admission">>))
    end, [{false, <<"masked_state">>},
          {true, <<"indexed_ordinary_state(masked_state)">>}]).

%% Identifier words are literal bindings, including names formerly targeted by rewriting.
-spec identifiers_are_rendered_without_textual_rebinding_test() -> ok.
identifiers_are_rendered_without_textual_rebinding_test() ->
    Text = iolist_to_binary(xls_collection_codegen:selection(
        #{admission_reductions => exclusive_epoch},
        #{ordinary_state => "intent", collection_state => "state", ordinary_result => "state_intent"})),
    ?assertEqual(<<"\n        let state_intent = collection_select_ordinary(intent);\n"
        "        let collection_intent = collection_select(state);\n">>, Text).

%% Distinct names reveal accidental sharing between reservation and collection sources.
-spec selection(map()) -> binary().
selection(Spec) ->
    iolist_to_binary(xls_collection_codegen:selection(Spec,
        #{ordinary_state => "masked_state", collection_state => "collector_state",
            ordinary_result => "next_mail"})).
