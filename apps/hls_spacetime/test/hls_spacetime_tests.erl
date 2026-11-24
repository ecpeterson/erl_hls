-module(hls_spacetime_tests).
-include_lib("eunit/include/eunit.hrl").

%% Saved fixture is a schema exercise, never a measured decoder recording.
-spec fixture() -> hls_spacetime:bundle().
fixture() ->
    {ok, [Bundle]} = file:consult(fixture_path()),
    Bundle.

%% Umbrella tests run from the repository root; keep the app-owned fixture explicit.
-spec fixture_path() -> file:filename().
fixture_path() ->
    filename:join(["apps", "hls_spacetime", "test_data", "spacetime_example.term"]).

%% Encoding retains the cycle domain and does not prune tied prerequisite identities.
-spec saved_example_test() -> ok.
saved_example_test() ->
    B = fixture(),
    ?assertMatch(
        #{
            events := 11,
            complete := true,
            mapping := #{mapped := 4, ambiguous := 1, physical_cells := 3}
        },
        hls_spacetime:validate(B)
    ),
    Json = json:decode(iolist_to_binary(hls_spacetime:encode(B))),
    ?assertEqual(<<"cycle">>, maps:get(<<"unit">>, Json)),
    ?assertEqual(<<"synthetic_fixture">>, maps:get(<<"evidence">>, Json)),
    #{events := Events} = B,
    Join = hd([E || E = #{id := <<"e7">>} <- Events]),
    ?assertEqual([<<"side">>, <<"read0">>], maps:get(inputs, Join)),
    ?assertEqual(B, fixture()).

%% A native timing report can locate a cell at its site without identifying the BEL.
-spec site_only_placement_test() -> ok.
site_only_placement_test() ->
    #{physical := #{cells := [Cell | Rest]} = Physical} = Bundle = fixture(),
    SiteOnly = Cell#{bel := null},
    Updated = Bundle#{physical := Physical#{cells := [SiteOnly | Rest]}},
    ?assertMatch(#{mapping := #{physical_cells := 3}}, hls_spacetime:validate(Updated)),
    ?assertError({spacetime, {invalid_physical_identifier, null}}, hls_spacetime:validate(Bundle#{physical := Physical#{
        cells := [SiteOnly#{site := null} | Rest]
    }})).

%% Only widthless computations can span cells without supplying a storage bit map.
-spec distributed_logic_test() -> ok.
distributed_logic_test() ->
    #{physical := #{bindings := Bindings} = Physical, resources := Resources} = Bundle = fixture(),
    Spread = [case B of
        #{resource := <<"dispatch">>} -> B#{disposition := distributed};
        _ -> B
    end || B <- Bindings],
    Measured = Bundle#{physical := Physical#{bindings := Spread}},
    ?assertMatch(#{mapping := #{mapped := 5}}, hls_spacetime:validate(Measured)),
    Encoded = [case R of
        #{id := <<"dispatch">>} -> R#{width => 2};
        _ -> R
    end || R <- Resources],
    ?assertError({spacetime, missing_distributed_bits}, hls_spacetime:validate(Measured#{resources := Encoded})).

%% The shared build contract preserves this artifact's map shape while spacetime keeps UTF-8 text.
-spec observation_build_contract_test() -> ok.
observation_build_contract_test() ->
    Bundle = #{build := Build} = fixture(),
    Shared = hls_observation_build:new(
        maps:get(source, Build),
        maps:get(rtl, Build),
        maps:get(observation, Build),
        maps:get(implementation, Build)
    ),
    ?assertEqual(hls_spacetime:validate(Bundle), hls_spacetime:validate(Bundle#{build := Shared})),
    Opaque = hls_observation_build:new(
        <<255>>, <<"rtl">>, <<"observation">>, <<"implementation">>
    ),
    ?assertError({spacetime, text}, hls_spacetime:validate(Bundle#{build := Opaque})).

%% Logical attribution can name multiple resources without adding dependencies or duplicating cells.
-spec event_resource_associations_test() -> ok.
event_resource_associations_test() ->
    B = event(fixture(), <<"e7">>, fun(E) ->
        E#{resources => [<<"dispatch">>, <<"delta">>]}
    end),
    ?assertEqual(hls_spacetime:validate(fixture()), hls_spacetime:validate(B)),
    #{<<"events">> := Events} = json:decode(iolist_to_binary(hls_spacetime:encode(B))),
    [Join] = [E || E = #{<<"id">> := <<"e7">>} <- Events],
    ?assertEqual([<<"dispatch">>, <<"delta">>], maps:get(<<"resources">>, Join)).

%% Resource references must resolve independently of event, activation and signal names.
-spec unknown_event_resource_test() -> ok.
unknown_event_resource_test() ->
    B = event(fixture(), <<"e7">>, fun(E) -> E#{resources => [<<"missing">>]} end),
    ?assertException(
        error, {spacetime, {unknown, event_resource, <<"missing">>}}, hls_spacetime:validate(B)
    ).

%% A repeated resource is one association, not evidence that an event uses it twice.
-spec duplicate_event_resource_test() -> ok.
duplicate_event_resource_test() ->
    B = event(fixture(), <<"e7">>, fun(E) ->
        E#{resources => [<<"dispatch">>, <<"dispatch">>]}
    end),
    ?assertException(
        error, {spacetime, {duplicate_event_resources, <<"e7">>}}, hls_spacetime:validate(B)
    ).

%% Table-driven corruptions target independent evidence claims, not merely parser behavior.
-spec reject_test_() -> [{string(), fun(() -> ok)}].
reject_test_() ->
    Cases = [
        {duplicate_event, fun(B = #{events := Es}) -> B#{events := [hd(Es) | Es]} end},
        {duplicate_version, fun(B = #{versions := Vs}) -> B#{versions := [hd(Vs) | Vs]} end},
        {unknown_input, fun(B) ->
            event(B, <<"e7">>, fun(E) -> E#{inputs := [<<"absent">>]} end)
        end},
        {unknown_producer, fun(B) ->
            version(B, <<"side">>, fun(V) -> V#{producer := <<"absent">>} end)
        end},
        {missing_interior, fun(B) -> remove_event(B, <<"e2">>) end},
        {missing_footer, fun(B) -> observer(B, fun(O) -> maps:remove(next_sequence, O) end) end},
        {complete_with_loss, fun(B) ->
            observer(remove_event(B, <<"e2">>), fun(O) -> O#{gaps := [gap()]} end)
        end},
        {future_version, fun(B) -> event(B, <<"e0">>, fun(E) -> E#{inputs := [<<"side">>]} end) end},
        {cycle_loop, fun(B) ->
            relation(B, #{
                source => <<"e5">>, target => <<"e5">>, kind => required, evidence => <<"bad">>
            })
        end},
        {cross_reset_input, fun(B) ->
            event(B, <<"e8">>, fun(E) -> E#{inputs := [<<"ff1">>]} end)
        end},
        {cross_reset_relation, fun(B) ->
            relation(B, #{
                source => <<"e0">>, target => <<"e8">>, kind => required, evidence => <<"bad">>
            })
        end},
        {activation_alias, fun(B) ->
            event(B, <<"e8">>, fun(E) -> E#{activation := <<"data-update">>} end)
        end},
        {out_of_epoch, fun(B) -> event(B, <<"e8">>, fun(E) -> E#{cycle := 9} end) end},
        {inexact_cycle, fun(B) -> event(B, <<"e8">>, fun(E) -> E#{cycle := 1 bsl 53} end) end},
        {hold_new_version, fun(B) ->
            event(B, <<"e2">>, fun(E) -> E#{outputs := [<<"ff1">>]} end)
        end},
        {write_reuses_version, fun(B) ->
            access(B, <<"e1">>, fun(A) -> A#{after_version := <<"ff0">>} end)
        end},
        {write_mask_bounds, fun(B) -> access(B, <<"e3">>, fun(A) -> A#{mask := 256} end) end},
        {masked_write_missing_old_word, fun(B) ->
            event(B, <<"e3">>, fun(E) -> E#{inputs := [<<"correction">>]} end)
        end},
        {stale_hold, fun(B) ->
            access(event(B, <<"e2">>, fun(E) -> E#{inputs := [<<"ff0">>]} end), <<"e2">>, fun(A) ->
                A#{version := <<"ff0">>}
            end)
        end},
        {bypass_storage_access, fun(B) ->
            event(B, <<"e7">>, fun(E) -> E#{inputs := [<<"ff0">>]} end)
        end},
        {wrong_read_latency, fun(B) -> event(B, <<"e6">>, fun(E) -> E#{cycle := 6} end) end},
        {wrong_read_address, fun(B) -> access(B, <<"e6">>, fun(A) -> A#{address := 1} end) end},
        {read_address_bounds, fun(B) -> access(B, <<"e4">>, fun(A) -> A#{address := 2} end) end},
        {read_wrong_collision_word, fun(B) ->
            access(event(B, <<"e4">>, fun(E) -> E#{inputs := [<<"m1">>]} end), <<"e4">>, fun(A) ->
                A#{version := <<"m1">>}
            end)
        end},
        {forbidden_collision, fun(B) ->
            resource(B, <<"memory">>, fun(R) -> R#{collision := forbidden} end)
        end},
        {missing_read_result, fun(B) ->
            event(version(B, <<"read0">>, fun(V) -> V#{storage := null} end), <<"e6">>, fun(E) ->
                maps:remove(access, E)
            end)
        end},
        {unsupported_collision, fun(B) ->
            resource(B, <<"memory">>, fun(R) -> R#{collision := no_change} end)
        end},
        {activity_is_not_dependency, fun(B) ->
            relation(B, #{
                source => <<"e0">>, target => <<"e7">>, kind => activity, evidence => <<"bad">>
            })
        end},
        {incompatible_build, fun(B = #{physical := P}) ->
            B#{physical := P#{build := (maps:get(build, P))#{rtl := <<"different">>}}}
        end},
        {missing_binding, fun(B = #{physical := P}) ->
            B#{physical := P#{bindings := tl(maps:get(bindings, P))}}
        end},
        {unknown_cell, fun(B) ->
            binding(B, <<"delta">>, fun(M) -> M#{cells := [<<"missing">>]} end)
        end},
        {non_utf8_catalogue, fun(B = #{physical := P}) ->
            B#{physical := P#{checkpoint := <<255>>}}
        end},
        {non_utf8_property, fun(B = #{physical := P}) ->
            [Cell | Cells] = maps:get(cells, P),
            B#{physical := P#{cells := [Cell#{properties := #{<<"INIT">> => <<255>>}} | Cells]}}
        end},
        {ambiguous_as_direct, fun(B) ->
            binding(B, <<"dispatch">>, fun(M) -> M#{disposition := direct} end)
        end},
        {synthetic_native_claim, fun(B = #{physical := P}) ->
            B#{physical := P#{evidence := native_measurement}}
        end}
    ],
    [
        {atom_to_list(Name), fun() ->
            ?assertException(error, {spacetime, _}, hls_spacetime:validate(Mutate(fixture())))
        end}
     || {Name, Mutate} <- Cases
    ].

%% An explicit gap remains usable as incomplete evidence, never silently repaired.
-spec known_loss_stays_incomplete_test() -> ok.
known_loss_stays_incomplete_test() ->
    B0 = remove_event(fixture(), <<"e2">>),
    %% Remove the separate resource-order relation whose endpoint was lost; no guessed replacement.
    B1 = B0#{relations := [], capture := (maps:get(capture, B0))#{complete := false}},
    B = observer(B1, fun(O) -> O#{gaps := [gap()]} end),
    ?assertMatch(#{complete := false}, hls_spacetime:validate(B)).

%% Write-first forwarding selects the new word while preserving response latency.
-spec write_first_collision_test() -> ok.
write_first_collision_test() ->
    B0 = resource(fixture(), <<"memory">>, fun(R) -> R#{collision := write_first} end),
    B = lists:foldl(
        fun(Id, Acc) ->
            access(event(Acc, Id, fun(E) -> E#{inputs := [<<"m1">>]} end), Id, fun(A) ->
                A#{version := <<"m1">>}
            end)
        end,
        B0,
        [<<"e4">>, <<"e6">>]
    ),
    ?assertMatch(#{complete := true}, hls_spacetime:validate(B)).

%% Replacement order alone does not make an overwritten value an input to the new value.
-spec full_overwrite_does_not_invent_data_dependency_test() -> ok.
full_overwrite_does_not_invent_data_dependency_test() ->
    B = event(fixture(), <<"e1">>, fun(E) -> E#{inputs := [<<"correction">>]} end),
    #{required_version_edges := Before} = hls_spacetime:validate(fixture()),
    %% ff0 is a root, so this change removes no producer edge but does remove a false data input.
    ?assertMatch(#{required_version_edges := Before}, hls_spacetime:validate(B)).

%% A passive hold observation does not reserve the memory read port.
-spec hold_and_read_same_cycle_test() -> ok.
hold_and_read_same_cycle_test() ->
    B = event(fixture(), <<"e8">>, fun(E) ->
        E#{
            inputs := [<<"m-carry">>],
            access := #{
                kind => hold,
                resource => <<"memory">>,
                address => 0,
                port => <<"r">>,
                version => <<"m-carry">>
            }
        }
    end),
    ?assertMatch(#{complete := true}, hls_spacetime:validate(B)).

%% Browser JSON parsers must not round wide masks before a viewer can interpret them.
-spec wide_mask_encoding_test() -> ok.
wide_mask_encoding_test() ->
    B0 = resource(fixture(), <<"delta">>, fun(R) -> R#{width := 64} end),
    B = access(B0, <<"e1">>, fun(A) -> A#{mask := (1 bsl 64) - 1} end),
    #{<<"events">> := Events} = json:decode(iolist_to_binary(hls_spacetime:encode(B))),
    [#{<<"access">> := #{<<"mask">> := Mask}}] = [E || E = #{<<"id">> := <<"e1">>} <- Events],
    ?assertEqual(<<"0xFFFFFFFFFFFFFFFF">>, Mask).

%% A read whose result falls outside the captured incarnation can remain pending.
-spec pending_read_at_tail_test() -> ok.
pending_read_at_tail_test() ->
    B0 = fixture(),
    B1 = event(B0, <<"e9">>, fun(E) -> E#{cycle := 13} end),
    B2 = remove_event(B1, <<"e10">>),
    B3 = B2#{versions := [V || V = #{id := Id} <- maps:get(versions, B2), Id =/= <<"read1">>]},
    B = observer(B3, fun(O) -> O#{next_sequence := 10} end),
    ?assertMatch(#{complete := true}, hls_spacetime:validate(B)).

%% Resource binding counts cannot multiply installed cells or turn unknowns into measured zero area.
-spec physical_coverage_test() -> ok.
physical_coverage_test() ->
    ?assertMatch(
        #{mapping := #{unmapped := 5, physical_cells := 0, catalogue_supplied := false}},
        hls_spacetime:validate((fixture())#{physical := null})
    ),
    B = binding(fixture(), <<"dispatch">>, fun(M) ->
        M#{disposition := optimized_away, cells := []}
    end),
    ?assertMatch(
        #{mapping := #{optimized_away := 1, mapped := 4, physical_cells := 3}},
        hls_spacetime:validate(B)
    ),
    Replicated = binding(fixture(), <<"dispatch">>, fun(M) -> M#{disposition := replicated} end),
    ?assertMatch(
        #{mapping := #{mapped := 5, physical_cells := 3}}, hls_spacetime:validate(Replicated)
    ).

%% Focused mutations preserve unrelated fixture identities.
-spec event(map(), binary(), fun((map()) -> map())) -> map().
event(B, Id, F) ->
    B#{
        events := [
            case E of
                #{id := Id} -> F(E);
                _ -> E
            end
         || E <- maps:get(events, B)
        ]
    }.
%% Change one value declaration, including deliberately inconsistent negative cases.
-spec version(map(), binary(), fun((map()) -> map())) -> map().
version(B, Id, F) ->
    B#{
        versions := [
            case V of
                #{id := Id} -> F(V);
                _ -> V
            end
         || V <- maps:get(versions, B)
        ]
    }.
%% Change one logical resource without silently updating its consumers.
-spec resource(map(), binary(), fun((map()) -> map())) -> map().
resource(B, Id, F) ->
    B#{
        resources := [
            case R of
                #{id := Id} -> F(R);
                _ -> R
            end
         || R <- maps:get(resources, B)
        ]
    }.
%% Mutate the selected event's storage descriptor.
-spec access(map(), binary(), fun((map()) -> map())) -> map().
access(B, Id, F) -> event(B, Id, fun(E) -> E#{access := F(maps:get(access, E))} end).
%% Mutate one resource's physical disposition and leave catalogue identities intact.
-spec binding(map(), binary(), fun((map()) -> map())) -> map().
binding(B = #{physical := P}, Id, F) ->
    B#{
        physical := P#{
            bindings := [
                case M of
                    #{resource := Id} -> F(M);
                    _ -> M
                end
             || M <- maps:get(bindings, P)
            ]
        }
    }.
%% Change the synthetic stream's counters or explicit gaps.
-spec observer(map(), fun((map()) -> map())) -> map().
observer(B = #{capture := C}, F) ->
    B#{capture := C#{observers := [F(O) || O <- maps:get(observers, C)]}}.
%% Remove an observation without renumbering its neighbors.
-spec remove_event(map(), binary()) -> map().
remove_event(B, Id) -> B#{events := [E || E = #{id := Other} <- maps:get(events, B), Other =/= Id]}.
%% Add a relationship, including an intentionally invalid endpoint or category.
-spec relation(map(), map()) -> map().
relation(B, R) -> B#{relations := [R | maps:get(relations, B)]}.
%% One declared missing interior sequence, with exclusive upper bound.
-spec gap() -> #{first_sequence := 2, next_sequence := 3, reason := binary()}.
gap() -> #{first_sequence => 2, next_sequence => 3, reason => <<"Explicitly dropped record">>}.

%% Read subsets survive encoding exactly and remain attached to the accepted request.
-spec selected_read_mask_test() -> ok.
selected_read_mask_test() ->
    Mask = 1 bsl 100,
    B0 = resource((fixture())#{physical := null}, <<"memory">>, fun(R) -> R#{width := 128} end),
    B1 = access(B0, <<"e4">>, fun(A) -> A#{read_mask => Mask} end),
    B2 = access(B1, <<"e6">>, fun(A) -> A#{read_mask => Mask} end),
    #{<<"events">> := Events} = json:decode(iolist_to_binary(hls_spacetime:encode(B2))),
    [Encoded] = [M || #{<<"id">> := <<"e4">>, <<"access">> := #{<<"read_mask">> := M}} <- Events],
    ?assertEqual(<<"0x10000000000000000000000000">>, Encoded).

%% Empty/out-of-width masks, changed responses and use on nonreads reject.
-spec invalid_read_masks_test() -> ok.
invalid_read_masks_test() ->
    lists:foreach(fun(Mask) ->
        B = access(fixture(), <<"e4">>, fun(A) -> A#{read_mask => Mask} end),
        ?assertException(error, {spacetime, {storage_read_mask, <<"e4">>}}, hls_spacetime:validate(B))
    end, [0, -1, 256, 1.5]),
    Request = access(fixture(), <<"e4">>, fun(A) -> A#{read_mask => 3} end),
    lists:foreach(fun(B) ->
        ?assertException(error, {spacetime, {storage_read_mask_mismatch, <<"e6">>}}, hls_spacetime:validate(B))
    end, [Request, access(Request, <<"e6">>, fun(A) -> A#{read_mask => 1} end)]),
    Write = access(fixture(), <<"e1">>, fun(A) -> A#{read_mask => 1} end),
    ?assertException(error, {spacetime, {storage_read_mask, <<"e1">>}}, hls_spacetime:validate(Write)).
