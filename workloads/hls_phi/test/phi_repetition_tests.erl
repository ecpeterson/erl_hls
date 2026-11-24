-module(phi_repetition_tests).
-moduledoc "Geometry, fault incidence and arithmetic checks for the periodic line.".
-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

%% The semantic graph has only three N-site families and no vertical ports.
-spec line_geometry_test() -> ok.
line_geometry_test() ->
    lists:foreach(fun(N) ->
        Plan = #{families := Families} = hls_topology:normalize(
            phi_repetition_topology:topology(N, 0)),
        ?assertEqual([data, phi, syndrome], lists:sort(
            [Id || #{id := Id, shape := [N0, 1]} <- Families, N0 =:= N])),
        lists:foreach(fun(X) ->
            ?assertEqual(#{east => {phi, (X+1) rem N, 0},
                west => {phi, (X+N-1) rem N, 0}, syndrome => {syndrome, X, 0}},
                destinations(Plan, phi, X)),
            ?assertEqual(#{east => {data, (X+1) rem N, 0}, west => {data, X, 0},
                phi => {phi, X, 0}}, destinations(Plan, syndrome, X)),
            ?assertEqual(#{east => {syndrome, X, 0}, west => {syndrome, (X+N-1) rem N, 0}},
                destinations(Plan, data, X))
        end, lists:seq(0, N-1))
    end, [2, 3, 8]).

%% A sampled Z fault is reported once to each adjacent weight-two check.
-spec data_fault_incidence_test() -> ok.
data_fault_incidence_test() ->
    {ok, configuring, Initial} = phenom_line_data_cell:init([]),
    {collecting, Cell0, consume} = phenom_line_data_cell:configuring(
        cast, #phenom_config{seed = 16#6d2b79f5, threshold = 16#80000000, x = 0, y = 0}, Initial),
    {collecting, Cell1, consume} = phenom_line_data_cell:collecting(
        cast, #phenom_query{step = 0, source = 2}, Cell0),
    ?assertEqual({collecting, Cell1, fail}, phenom_line_data_cell:collecting(
        cast, #phenom_query{step = 0, source = 2}, Cell1)),
    lists:foreach(fun(Source) ->
        ?assertEqual({collecting, Cell0, fail}, phenom_line_data_cell:collecting(
            cast, #phenom_query{step = 0, source = Source}, Cell0))
    end, [0, 1, 3, 8]),
    {reporting, Cell2, consume} = phenom_line_data_cell:collecting(
        cast, #phenom_query{step = 0, source = 4}, Cell1),
    {Cell2, Reports} = phenom_line_data_cell:reporting(enter, collecting, Cell2),
    ?assertEqual([{cast, east, #phenom_data{step = 0, source = 4, flags = 1}},
        {cast, west, #phenom_data{step = 0, source = 2, flags = 1}}], Reports),
    ?assertEqual(z, element(9, Cell2)),
    %% Route the real reports, alongside quiet reports from every other site.
    N = 5,
    Plan = hls_topology:normalize(phi_repetition_topology:topology(N, 0)),
    Checks0 = maps:from_list([{X, syndrome(0)} || X <- lists:seq(0, N-1)]),
    Checks = lists:foldl(fun(DataX, Acc0) ->
        lists:foldl(fun({cast, Port, Message}, Acc) ->
            {syndrome, CheckX, 0} = maps:get(Port, destinations(Plan, data, DataX)),
            Present = case DataX of 2 -> 1; _ -> 0 end,
            {_, Updated, consume} = phenom_line_syndrome_cell:collecting(
                cast, Message#phenom_data{flags = Present}, maps:get(CheckX, Acc)),
            Acc#{CheckX => Updated}
        end, Acc0, Reports)
    end, Checks0, lists:seq(0, N-1)),
    ?assertEqual([1, 2], [X || {X, Check} <- lists:sort(maps:to_list(Checks)),
        element(1, release(Check, 0)) =:= 1]).

%% A measurement fault creates an event when it starts and when it disappears.
-spec measurement_temporal_boundaries_test() -> ok.
measurement_temporal_boundaries_test() ->
    First = complete_check(syndrome(16#80000000), 0, 0, 0),
    {1, Next} = release(First, 0),
    Second = complete_check(Next, 1, 0, 0),
    {1, _} = release(Second, 1),
    %% Two simultaneous data faults cancel at their common check.
    {0, _} = release(complete_check(syndrome(0), 0, 1, 1), 0),
    ok.

%% Reductions wait for two contributions; distinct labels survive N=2 aliasing.
-spec phi_reductions_test() -> ok.
phi_reductions_test() ->
    {ok, configuring, Initial} = phi_line_cell:init([]),
    {measuring, Configured, consume} = phi_line_cell:configuring(
        cast, #phi_config{seed = 1}, Initial),
    {gathering, Cell, consume} = phi_line_cell:measuring(
        cast, #phenom_anyon{step = 0, flags = 0, x = 0, y = 0}, Configured),
    {Cell, Diffusion} = phi_line_cell:gathering(enter, measuring, Cell),
    ?assertMatch([{open_reduction, diffusion, 0, {count, 2}, _},
        {cast, east, _}, {cast, west, _}], Diffusion),
    {Cell, Comparison} = phi_line_cell:comparing(enter, gathering, Cell),
    ?assertMatch([{open_reduction, comparison, 0, {members, [2, 4]}, _},
        {cast, east, _}, {cast, west, _}], Comparison),
    {_AdvancedRandom, Movement} = phi_line_cell:flipping(enter, comparing, Cell),
    ?assertMatch([{open_reduction, movement, 0, {count, 2}, _},
        {cast, east, _}, {cast, west, _}], Movement).

%% Direction tables preserve output order, opposite source labels and correction-after-moves.
-spec geometry_broadcasts_test() -> ok.
geometry_broadcasts_test() ->
    Geometries = [{phi_line_cell, [{east, 2, 4}, {west, 4, 2}]},
        {phi_halo_cell, [{north, 1, 8}, {east, 2, 4}, {west, 4, 2}, {south, 8, 1}]}],
    lists:foreach(fun({Module, Directions}) ->
        lists:foreach(fun({Seed, Anyon, Direction}) ->
            Common = {cell, 7, 84, [11, 13], Direction, Anyon, Seed, 4, 5, 0, 0},
            Cell = case Module of
                phi_line_cell -> append_staging(Common, [0, 0], 0);
                phi_halo_cell -> Common
            end,
            {Cell, [_Open | Broadcasts]} = Module:comparing(enter, gathering, Cell),
            ?assertEqual([{cast, Port, #phi0{step = 7, source = Source, value = 11}}
                || {Port, _, Source} <- Directions], Broadcasts),
            {Moved, [Open | Actions]} = Module:flipping(enter, comparing, Cell),
            ?assertMatch({open_reduction, movement, 7, _, _}, Open),
            NextRandom = hls_prng:xorshift32(Seed),
            Present = case Anyon =:= 1 andalso Direction =/= 0 andalso
                    (NextRandom bsr 31) =:= 1 of true -> 1; false -> 0 end,
            ExpectedCommon = setelement(7, setelement(6, Common, Anyon bxor Present), NextRandom),
            ?assertEqual(ExpectedCommon, case Module of
                phi_line_cell -> common_cell(Moved);
                phi_halo_cell -> Moved
            end),
            {Moves, Corrections} = lists:split(length(Directions), Actions),
            ?assertEqual([{cast, Port, #anyon_move{step = 7,
                present = case Mask =:= Direction of true -> Present; false -> 0 end}}
                || {Port, Mask, _} <- Directions], Moves),
            ?assertEqual(case Present of
                0 -> [];
                1 -> [{cast, correction, #phi_correction{step = 7, x = 4, y = 5,
                    direction = Direction}}]
            end, Corrections)
        end, [{Seed, Anyon, Direction} || Seed <- [1, 8192, 16#6d2b79f5],
            Anyon <- [0, 1], Direction <- lists:seq(0, 15)])
    end, Geometries).

%% Specializing the two-edge tie preserves the grid selector's exact choice.
-spec line_tie_equivalence_test() -> ok.
line_tie_equivalence_test() ->
    lists:foreach(fun(Seed) ->
        Grid = {cell, 0, 0, [0, 0], 0, 0, Seed, 0, 0, 0, 0},
        Line = append_staging(Grid, [0, 0], 0),
        lists:foreach(fun(Mask) ->
            Event = {reduction_complete, comparison, 0, {phi_fold, 17, Mask}},
            {GridPhase, GridNext, GridDirective} =
                phi_halo_cell:comparing(internal, Event, Grid),
            {LinePhase, LineNext, LineDirective} =
                phi_line_cell:comparing(internal, Event, Line),
            ?assertEqual({GridPhase, GridNext, GridDirective},
                {LinePhase, common_cell(LineNext), LineDirective}),
            ?assertEqual({[0, 0], 0}, staging(LineNext))
        end, [0, 2, 4, 6])
    end, [(I * 16#9e3779b9) band 16#ffffffff || I <- lists:seq(1, 1024)]).

%% The line recurrence preserves a uniform gauge and rounds/saturates exactly.
-spec line_arithmetic_test() -> ok.
line_arithmetic_test() ->
    Values = [-(1 bsl 31), -(1 bsl 30), -1, 0, 1, 1 bsl 30, (1 bsl 31)-1],
    lists:foreach(fun(V) ->
        ?assertEqual([V, V], phi_field:relax_line(0, [V, V], 2*V, 2*V))
    end, Values),
    lists:foreach(fun({A, P, Q, S, T}) ->
        Expected = [clip((A bsl 16)+round_eighth(4*P+2*Q+S)),
            clip(round_eighth(P+5*Q+T))],
        Numerators = phi_field:line_numerators([P, Q], S, T),
        ?assertEqual([4*P+2*Q+S, P+5*Q+T], Numerators),
        ?assertEqual(Expected, phi_field:finish_line(A, Numerators)),
        ?assertEqual(Expected, phi_field:relax_line(A, [P, Q], S, T))
    end, [{A, P, Q, 2*V, -V} || A <- [0, 1], P <- Values, Q <- Values, V <- Values]),
    lists:foreach(fun(S) ->
        Expected = [round_eighth(S), round_eighth(S)],
        ?assertEqual(Expected, phi_field:relax_line(0, [0, 0], S, S)),
        ?assertEqual(Expected, phi_field:finish_line(0, [S, S]))
    end, lists:seq(-64, 64)).

%% The source action stores partials; repeated entry evaluates the same pure suffix.
-spec line_diffusion_entry_retries_test() -> ok.
line_diffusion_entry_retries_test() ->
    Cell = line_cell(0, 0, [40, 20], 1),
    {repeat_phase, Partial, consume} = phi_line_cell:gathering(internal,
        {reduction_complete, diffusion, 0, {phi_fold, 16, 24}}, Cell),
    ?assertEqual({cell, 0, 1, [40, 20], 0, 1, 0, 0, 0, 0, 0}, common_cell(Partial)),
    ?assertEqual({[216, 164], 1}, staging(Partial)),
    {Entered, Actions} = Entry = phi_line_cell:gathering(enter, gathering, Partial),
    ?assertEqual({cell, 0, 1, [65563, 21], 0, 1, 0, 0, 0, 0, 0}, common_cell(Entered)),
    ?assertEqual({[0, 0], 0}, staging(Entered)),
    ?assertMatch([{open_reduction, diffusion, 1, {count, 2}, _},
        {cast, east, #phi{epoch = 1, values = [65563, 21]}},
        {cast, west, #phi{epoch = 1, values = [65563, 21]}}], Actions),
    %% A blocked caller retains Partial, not the uncommitted result of entry.
    ?assertEqual(Entry, phi_line_cell:gathering(enter, gathering, Partial)),
    ?assertEqual(Entry, phi_line_cell:gathering(enter, gathering, Entered)).

%% The final diffusion round finalizes before broadcasting comparison values.
-spec line_final_round_entry_test() -> ok.
line_final_round_entry_test() ->
    Cell = line_cell(0, 11, [-40, 20], 1),
    {comparing, Partial, consume} = phi_line_cell:gathering(internal,
        {reduction_complete, diffusion, 11, {phi_fold, -9, 17}}, Cell),
    ?assertEqual({[-129, 77], 1}, staging(Partial)),
    {Entered, Actions} = Entry = phi_line_cell:comparing(enter, gathering, Partial),
    ?assertEqual({cell, 0, 12, [65520, 10], 0, 1, 0, 0, 0, 0, 0}, common_cell(Entered)),
    ?assertEqual({[0, 0], 0}, staging(Entered)),
    ?assertMatch([{open_reduction, comparison, 0, {members, [2, 4]}, _},
        {cast, east, #phi0{step = 0, source = 4, value = 65520}},
        {cast, west, #phi0{step = 0, source = 2, value = 65520}}], Actions),
    ?assertEqual(Entry, phi_line_cell:comparing(enter, gathering, Partial)),
    ?assertEqual(Entry, phi_line_cell:comparing(enter, gathering, Entered)).

%% Startup and ordinary entry must ignore stale, explicitly inactive partials.
-spec line_inactive_partial_entry_test() -> ok.
line_inactive_partial_entry_test() ->
    {ok, configuring, Initial} = phi_line_cell:init([]),
    ?assertEqual({[0, 0], 0}, staging(Initial)),
    Cell = append_staging(common_cell(line_cell(0, 0, [12, -9], 1)), [4000, -4000], 0),
    {Cell, Diffusion} = phi_line_cell:gathering(enter, measuring, Cell),
    ?assertMatch([_, {cast, east, #phi{values = [12, -9]}},
        {cast, west, #phi{values = [12, -9]}}], Diffusion),
    {Cell, Comparison} = phi_line_cell:comparing(enter, gathering, Cell),
    ?assertMatch([_, {cast, east, #phi0{value = 12}},
        {cast, west, #phi0{value = 12}}], Comparison).

%% Wrapping to epoch zero still owns a numerical result awaiting entry.
-spec line_wrapping_final_round_test() -> ok.
line_wrapping_final_round_test() ->
    Last = (1 bsl 32) - 1,
    Cell = line_cell(Last, Last, [7, -9], 0),
    {comparing, Partial, consume} = phi_line_cell:gathering(internal,
        {reduction_complete, diffusion, Last, {phi_fold, -5, 9}}, Cell),
    ?assertEqual({[5, -29], 1}, staging(Partial)),
    {Entered, Actions} = phi_line_cell:comparing(enter, gathering, Partial),
    ?assertEqual({cell, Last, 0, [1, -4], 0, 0, 0, 0, 0, 0, 0}, common_cell(Entered)),
    ?assertEqual({[0, 0], 0}, staging(Entered)),
    ?assertMatch([{open_reduction, comparison, Last, _, _},
        {cast, east, #phi0{step = Last, value = 1}},
        {cast, west, #phi0{step = Last, value = 1}}], Actions).

%% Independent finishing oracle spans signed half ties and both saturation boundaries.
-spec line_finishing_boundaries_test() -> ok.
line_finishing_boundaries_test() ->
    Limits = [-(1 bsl 35), (1 bsl 35)-1],
    Numerators = Limits ++ lists:seq(-9, 9) ++
        [8 * N + R || N <- [-(1 bsl 31), (1 bsl 31)-1], R <- [-5, -4, -3, 0, 3, 4, 5]],
    lists:foreach(fun(A) ->
        lists:foreach(fun(N) ->
            ?assertEqual([clip((A bsl 16)+round_eighth(N)), clip(round_eighth(N))],
                phi_field:finish_line(A, [N, N]))
        end, Numerators)
    end, [0, 1]).

%% Build a line fixture through its real initializer, preserving initialized metadata.
-spec line_cell(hls_nums:u32(), hls_nums:u32(), phi_field:field(), 0 | 1) -> tuple().
line_cell(Step, Epoch, Field, Anyon) ->
    {ok, configuring, Initial} = phi_line_cell:init([]),
    {cell, _, _, _, Best, _, Random, X, Y, Quiet, Valid} = common_cell(Initial),
    append_staging({cell, Step, Epoch, Field, Best, Anyon, Random, X, Y, Quiet, Valid},
        [0, 0], 0).

%% Compare shared semantics without requiring line and grid storage to have one ABI.
-spec common_cell(tuple()) -> tuple().
common_cell({cell, Step, Epoch, Field, Best, Anyon, Random, X, Y, Quiet, Valid,
        _Numerators, _Pending}) ->
    {cell, Step, Epoch, Field, Best, Anyon, Random, X, Y, Quiet, Valid}.

%% The line's two appended fields are explicit test fixtures, not wire payloads.
-spec append_staging(tuple(), phi_field:line_numerators(), 0 | 1) -> tuple().
append_staging({cell, Step, Epoch, Field, Best, Anyon, Random, X, Y, Quiet, Valid},
        Numerators, Pending) ->
    {cell, Step, Epoch, Field, Best, Anyon, Random, X, Y, Quiet, Valid, Numerators, Pending}.

%% Inspect the source staging fields without exposing positional reads throughout tests.
-spec staging(tuple()) -> {phi_field:line_numerators(), 0 | 1}.
staging({cell, _, _, _, _, _, _, _, _, _, _, Numerators, Pending}) ->
    {Numerators, Pending}.

%% East crosses the seam; west addresses the data immediately before the check.
-spec correction_geometry_test() -> ok.
correction_geometry_test() ->
    ?assertEqual({{0, 0}, z}, phi_repetition_topology:correction_update(
        #phi_correction{step = 0, x = 4, y = 0, direction = 2}, 5)),
    ?assertEqual({{4, 0}, z}, phi_repetition_topology:correction_update(
        #phi_correction{step = 0, x = 4, y = 0, direction = 4}, 5)),
    ?assertError(badarg, phi_repetition_topology:correction_update(
        #phi_correction{step = 0, x = 4, y = 0, direction = 1}, 5)).

%% Ignore observation outputs; all actor recipients must lie on the line.
-spec destinations(hls_topology:plan(), atom(), non_neg_integer()) -> map().
destinations(Plan, Family, X) ->
    maps:from_list([{Port, Id} || #{source := {_, Port}, recipients := [{actor, Id}]} <-
        hls_logical_topology:routes_for_instance(Plan, Family, [X, 0])]).

%% Configure a check with the known first-hit/second-miss PRNG stream.
-spec syndrome(hls_nums:u32()) -> tuple().
syndrome(Threshold) ->
    {ok, configuring, Initial} = phenom_line_syndrome_cell:init([]),
    {collecting, Cell, consume} = phenom_line_syndrome_cell:configuring(
        cast, #phenom_config{seed = 16#6d2b79f5, threshold = Threshold, x = 0, y = 0}, Initial),
    {Ready, _} = phenom_line_syndrome_cell:collecting(enter, configuring, Cell),
    Ready.

%% Two data reports complete the check, without a third or fourth participant.
-spec complete_check(tuple(), non_neg_integer(), 0 | 1, 0 | 1) -> tuple().
complete_check(Cell0, Step, East, West) ->
    {collecting, Cell1, consume} = phenom_line_syndrome_cell:collecting(
        cast, #phenom_data{step = Step, source = 2, flags = East}, Cell0),
    {announcing, Cell2, consume} = phenom_line_syndrome_cell:collecting(
        cast, #phenom_data{step = Step, source = 4, flags = West}, Cell1),
    Cell2.

%% Extract the announced detection event and the next check's empty join.
-spec release(tuple(), non_neg_integer()) -> {0 | 1, tuple()}.
release(Cell0, Step) ->
    {collecting, Cell1, consume} = phenom_line_syndrome_cell:announcing(
        cast, #phenom_request{step = Step}, Cell0),
    {Cell2, [{cast, phi, #phenom_anyon{flags = Flags}} | _]} =
        phenom_line_syndrome_cell:collecting(enter, announcing, Cell1),
    {Flags band 1, Cell2}.

%% Independent nearest-integer oracle: signed ties round away from zero.
-spec round_eighth(integer()) -> integer().
round_eighth(N) ->
    Magnitude = abs(N),
    Rounded = Magnitude div 8 + case Magnitude rem 8 >= 4 of true -> 1; false -> 0 end,
    case N < 0 of true -> -Rounded; false -> Rounded end.

%% Clamp after rounding and source injection.
-spec clip(integer()) -> integer().
clip(N) -> min((1 bsl 31)-1, max(-(1 bsl 31), N)).
