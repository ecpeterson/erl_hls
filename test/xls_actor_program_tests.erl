-module(xls_actor_program_tests).
-moduledoc "Checks complete effect views and immutable source-snapshot ownership; these are compiler-interface regressions, not protocol or hardware proofs.".
-include_lib("eunit/include/eunit.hrl").

%% Every phase and conditional layout participates; aliases retain layout-local offsets.
-spec complete_entry_effects_test() -> ok.
complete_entry_effects_test() ->
    Program = xls_actor_program:from_file("test/xls_entry_storage_fixture.erl", []),
    Effects = xls_actor_program:entry_effects(Program),
    ?assertEqual(12, length(Effects)),
    ?assertEqual([{repeated, 3}, {independent, 3}, {conditional, 6}],
        [{Phase, length([E || E = #{phase := P} <- Effects, P =:= Phase])}
            || Phase <- [repeated, independent, conditional]]),
    Layouts = lists:usort([{P, L} || #{phase := P, layout := L} <- Effects]),
    ?assertEqual(4, length(Layouts)),
    lists:foreach(fun({Phase, Layout}) ->
        ?assertEqual([{0, first}, {1, second}, {2, third}],
            [{O, Port} || #{phase := P, layout := L, order := O, port := Port} <- Effects,
                P =:= Phase, L =:= Layout])
    end, Layouts),
    Repeated = [E || E = #{phase := repeated} <- Effects],
    Independent = [E || E = #{phase := independent} <- Effects],
    ?assertEqual([0, 0, 0], [maps:get(offset, field(key, E)) || E <- Repeated]),
    ?assertEqual([0, 32, 0], [maps:get(offset, field(key, E)) || E <- Independent]),
    ?assertEqual([<<1:8>>, <<2:8>>, <<3:8>>],
        [maps:get(constant, field(direction, E)) || E <- Repeated]).

%% Full field metadata survives the view, including partial slices and aliased storage.
-spec partial_fields_and_aliases_test() -> ok.
partial_fields_and_aliases_test() ->
    Program = xls_actor_program:from_file("test/xls_known_bits_fixture.erl", []),
    [First, Second] = xls_actor_program:entry_effects(Program),
    ?assertMatch(#{phase := active, order := 0, port := first, tag := packet}, First),
    ?assertMatch(#{phase := active, order := 1, port := second, tag := packet}, Second),
    ?assertEqual(maps:get(layout, First), maps:get(layout, Second)),
    ?assertEqual(maps:get(fields, First), maps:get(fields, Second)),
    ?assertMatch(#{known := #{mask := 16#f0f0, value := 16#8060},
        slices := [{0, 4}, {8, 4}], offset := 0}, field(coded, First)),
    ?assertMatch(#{known := #{mask := 10, value := 2},
        slices := [{0, 1}, {2, 1}, {4, 1}], offset := 8}, field(small, First)),
    ?assertMatch(#{known := #{mask := 16#ffff, value := 0}, slices := []}, field(zeroed, First)),
    ?assertNot(maps:is_key(known, field(opaque, First))),
    ?assertNot(maps:is_key(slices, field(opaque, First))).

%% A selected or hand-built map is not a program, even with plausible field names.
-spec supplied_artifacts_are_rejected_test() -> ok.
supplied_artifacts_are_rejected_test() ->
    Invalid = #{spec => #{entries => []}, plan => #{}, entry_effects => []},
    ?assertError(function_clause, xls_actor_program:spec(Invalid)),
    ?assertError(function_clause, xls_actor_program:plan(Invalid)),
    ?assertError(function_clause, xls_actor_program:entry_effects(Invalid)).

%% Old snapshots stay usable after source edits/removal; only fresh compilation observes edits.
-spec source_snapshot_lifetime_test() -> ok.
source_snapshot_lifetime_test() ->
    Root = filename:join("_build", "actor-program-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    File = filename:join(Root, "actor.erl"),
    ok = filelib:ensure_dir(File),
    {ok, Original} = file:read_file("test/xls_known_bits_fixture.erl"),
    try
        ok = file:write_file(File, Original),
        Program = xls_actor_program:from_file(File, []),
        Spec = xls_actor_program:spec(Program), Plan = xls_actor_program:plan(Program),
        Effects = xls_actor_program:entry_effects(Program),
        Before = xls_statem_plan:manifest(Plan),
        Changed = binary:replace(Original, <<"bor 16#8040">>, <<"bor 16#8080">>),
        ?assertNotEqual(Original, Changed),
        ok = file:write_file(File, Changed),
        Fresh = xls_actor_program:from_file(File, []),
        After = xls_statem_plan:manifest(xls_actor_program:plan(Fresh)),
        ?assertNotEqual(maps:get(source_sha256, Before), maps:get(source_sha256, After)),
        ?assertNotEqual(Effects, xls_actor_program:entry_effects(Fresh)),
        ?assertError(stale_statem_plan, xls_statem_plan:validate(File, [], Plan)),
        ok = file:delete(File),
        ?assertEqual(Spec, xls_actor_program:spec(Program)),
        ?assertEqual(Plan, xls_actor_program:plan(Program)),
        ?assertEqual(Effects, xls_actor_program:entry_effects(Program))
    after
        file:delete(File), file:del_dir(Root)
    end.

%% Find one schema field without changing its metadata or assuming declaration position.
-spec field(atom(), xls_actor_program:entry_effect()) -> map().
field(Name, #{fields := Fields}) ->
    [Field] = [F || F = #{name := N} <- Fields, N =:= Name],
    Field.
