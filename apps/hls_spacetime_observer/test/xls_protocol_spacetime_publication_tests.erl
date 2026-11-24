-module(xls_protocol_spacetime_publication_tests).
-moduledoc "Finite synthetic witnesses of publication ownership attribution. They exercise pending masks, concrete leases and endpoint arbiters without compiling hardware or claiming numerical equivalence.".
-include_lib("eunit/include/eunit.hrl").

%% Two simultaneous identical payloads remain distinct occurrences under independent endpoint stalls.
-spec independent_endpoint_identity_test() -> ok.
independent_endpoint_identity_test() ->
    P = plan([source(0, 1, [1]), source(1, 1, [1])], [],
        [endpoint(0, [0]), endpoint(1, [1])]),
    Rows = [#{}, merge([publisher(0, 0, 1, 1), publisher(1, 0, 1, 1)]),
        merge([publisher(0, 1, 0, 0), publisher(1, 1, 1, 0), port(0, 1, 1), port(1, 1, 0)]),
        merge([publisher(0, 0, 0, 0), publisher(1, 1, 0, 0), port(0, 0, 1), port(1, 1, 1)])],
    Events = [pub(<<"a">>, 1, 0), pub(<<"b">>, 1, 1), transfer(<<"x">>, 2, 0), transfer(<<"y">>, 3, 1)],
    {T, B} = fixture(P, Rows, Events),
    #{bundle := Joined, publication := #{refinements := R, pending := []}} =
        xls_protocol_spacetime_publication:attach(P, T, B),
    ?assertEqual([{<<"a">>, <<"x">>}, {<<"b">>, <<"y">>}],
        [{maps:get(producer, X), maps:get(consumer, X)} || X <- R]),
    ?assertEqual([maps:get(id, E) || E <- maps:get(events, B)],
        [maps:get(id, E) || E <- maps:get(events, Joined)]),
    ?assertEqual(<<"a">>, maps:get(producer, version(<<"x/in">>, Joined))),
    ?assertEqual(<<"b">>, maps:get(producer, version(<<"y/in">>, Joined))).

%% A stalled endpoint retains its selected source even while another publication remains available.
-spec held_endpoint_owner_test() -> ok.
held_endpoint_owner_test() ->
    P = plan([source(0, 1, [1]), source(1, 1, [1])], [], [endpoint(0, [0, 1])]),
    Rows = [#{}, merge([publisher(0, 0, 1, 1), publisher(1, 0, 1, 1)]),
        merge([publisher(0, 1, 1, 0), publisher(1, 1, 1, 0), port(0, 1, 0), arbiter(0, {0, 0, 0}, {0, 1, 0})]),
        merge([publisher(0, 1, 0, 0), publisher(1, 1, 1, 0), port(0, 1, 1), arbiter(0, {0, 1, 0}, {1, 0, 0})]),
        merge([publisher(0, 0, 0, 0), publisher(1, 1, 0, 0), port(0, 1, 1), arbiter(0, {1, 0, 0}, {0, 0, 0})])],
    {T, B} = fixture(P, Rows, [pub(<<"a">>, 1, 0), pub(<<"b">>, 1, 1),
        transfer(<<"x">>, 3, 0), transfer(<<"y">>, 4, 0)]),
    #{publication := #{refinements := R}} = xls_protocol_spacetime_publication:attach(P, T, B),
    ?assertEqual([<<"a">>, <<"b">>], [maps:get(producer, X) || X <- R]),
    BadRows = lists:sublist(Rows, 3) ++ [(lists:nth(4, Rows))#{<<"arb/0/cursor/d">> := 0}, lists:nth(5, Rows)],
    {BadTrace, _} = fixture(P, BadRows, []),
    ?assertException(error, {spacetime_publication, {endpoint_transition, _, _}},
        xls_protocol_spacetime_publication:attach(P, BadTrace, B)).

%% Arrival identity refines the exact encoded payload D root, preserving the original FF access.
-spec capture_write_lineage_test() -> ok.
capture_write_lineage_test() ->
    Payload = reg(<<"payload">>, 16),
    Slot = #{link => 0, slot => 0, source => 0, output => 0, sequences => [0],
        owner => reg(<<"owner">>, 2), payload => Payload},
    P = plan([source(0, 1, [1])], [Slot], []),
    Rows = [#{}, publisher(0, 0, 1, 1), merge([publisher(0, 1, 0, 0),
        sample_reg(<<"owner">>, 0, 1), sample_reg(<<"payload">>, 7, 7)])],
    Arrival = event(<<"arrive">>, 2, <<"link/0/0">>, <<"arrival">>),
    Write = (event(<<"write">>, 2, <<"capture">>, <<"register_write">>))#{access => #{
        kind => write, resource => <<"register/payload">>, address => 0, port => <<"write">>,
        before => <<"before">>, after_version => <<"write/out">>, mask => (1 bsl 16) - 1}},
    {T, B0} = fixture(P, Rows, [pub(<<"a">>, 1, 0), Arrival, Write]),
    Storage = #{resource => <<"register/payload">>, address => 0},
    Resource = #{id => <<"register/payload">>, kind => ff, width => 16, depth => 1,
        ports => #{<<"write">> => write}, read_latency => 0, collision => forbidden,
        reset => reinitialize, evidence => <<"Synthetic encoded capture word">>},
    Versions = [case maps:get(id, V) of <<"write/out">> -> V#{storage := Storage}; _ -> V end
        || V <- maps:get(versions, B0)],
    Before = #{id => <<"before">>, producer => root, origin => initial, incarnation => <<"reset/0">>,
        storage => Storage, evidence => <<"Synthetic initial word">>},
    B = B0#{resources := [Resource], versions := [Before | Versions]},
    #{bundle := Joined, publication := #{refinements := [A, W]}} =
        xls_protocol_spacetime_publication:attach(P, T, B),
    ?assertEqual({<<"a">>, <<"arrive">>, arrival},
        {maps:get(producer, A), maps:get(consumer, A), maps:get(kind, A)}),
    ?assertEqual({<<"arrive">>, <<"write">>, capture_write},
        {maps:get(producer, W), maps:get(consumer, W), maps:get(kind, W)}),
    [OldWrite] = [E || E = #{id := <<"write">>} <- maps:get(events, B)],
    [NewWrite] = [E || E = #{id := <<"write">>} <- maps:get(events, Joined)],
    ?assertEqual(maps:without([evidence], OldWrite), maps:without([evidence], NewWrite)),
    ?assertEqual(<<"arrive">>, maps:get(producer, version(<<"write/in">>, Joined))).

%% Reset retires the old publication; an equal post-reset occurrence starts a fresh ordinal sequence.
-spec reset_and_pending_test() -> ok.
reset_and_pending_test() ->
    P = plan([source(0, 1, [1])], [], [endpoint(0, [0])]),
    Rows = [#{}, publisher(0, 0, 1, 1), #{<<"reset">> => 1}, #{}, publisher(0, 0, 1, 1)],
    New = (pub(<<"new">>, 4, 0))#{incarnation => <<"reset/1">>},
    {T, B} = fixture(P, Rows, [pub(<<"old">>, 1, 0), New]),
    #{publication := #{refinements := [], retired := [#{cycle := 2, publications := [Old]}], pending := [Pending]}} =
        xls_protocol_spacetime_publication:attach(P, T, B),
    ?assertEqual(<<"old">>, maps:get(event, Old)),
    ?assertEqual(<<"new">>, maps:get(event, Pending)),
    ?assertEqual(<<"reset/1">>, maps:get(incarnation, Pending)),
    ?assertEqual(0, maps:get(ordinal, Pending)).

%% Already-busy work has no observed admission and must not borrow an earlier or equal publication.
-spec carry_in_remains_unknown_test() -> ok.
carry_in_remains_unknown_test() ->
    P = plan([source(0, 1, [1])], [], [endpoint(0, [0])]),
    Rows = [publisher(0, 1, 1, 0), merge([publisher(0, 1, 0, 0), port(0, 1, 1)])],
    {T, B} = fixture(P, Rows, [transfer(<<"x">>, 1, 0)]),
    #{bundle := B, publication := #{refinements := [], unresolved := [#{reason := publication_carry_in}]}} =
        xls_protocol_spacetime_publication:attach(P, T, B),
    ok.

%% Each output retires one lowest pending sequence; clearing a later bit or losing an output rejects.
-spec retirement_order_test() -> ok.
retirement_order_test() ->
    P = plan([source(0, 2, [3])], [], [endpoint(0, [0])]),
    Rows = [#{}, publisher(0, 0, 3, 1), merge([publisher(0, 3, 2, 0), port(0, 1, 1)]),
        merge([publisher(0, 2, 0, 0), port(0, 1, 1)])],
    {T, B} = fixture(P, Rows, [pub(<<"a">>, 1, 0), transfer(<<"x">>, 2, 0), transfer(<<"y">>, 3, 0)]),
    #{publication := #{refinements := R}} = xls_protocol_spacetime_publication:attach(P, T, B),
    ?assertEqual([0, 1], [maps:get(sequence, X) || X <- R]),
    BadRows = lists:sublist(Rows, 2) ++ [merge([publisher(0, 3, 1, 0), port(0, 1, 1)])],
    {BadTrace, BadGraph} = fixture(P, BadRows, [pub(<<"a">>, 1, 0)]),
    ?assertError({spacetime_publication, {publication_order, 0, 0, 2}},
        xls_protocol_spacetime_publication:attach(P, BadTrace, BadGraph)),
    Unmapped = P#{endpoints := []},
    ?assertError({spacetime_publication, {unmatched_retirement, 2, [{0, 0}]}},
        xls_protocol_spacetime_publication:attach(Unmapped, T, B)).

%% Existing resolved roots cannot be relabelled and same-edge retirement cannot admit another publication.
-spec contradictory_identity_test() -> ok.
contradictory_identity_test() ->
    P = plan([source(0, 1, [1])], [], [endpoint(0, [0])]),
    Rows = [#{}, publisher(0, 0, 1, 1), merge([publisher(0, 1, 0, 0), port(0, 1, 1)])],
    {T, B} = fixture(P, Rows, [pub(<<"a">>, 1, 0), transfer(<<"x">>, 2, 0)]),
    Versions = [case maps:get(id, V) of <<"x/in">> -> V#{origin := carry_in}; _ -> V end
        || V <- maps:get(versions, B)],
    ?assertException(error, {badmatch, _}, xls_protocol_spacetime_publication:attach(P, T, B#{versions := Versions})),
    {BadTrace, _} = fixture(P, lists:sublist(Rows, 2) ++ [(lists:nth(3, Rows))#{<<"source/0/accept">> := 1}], []),
    ?assertError({spacetime_publication, {publication_admission, 0, 2}},
        xls_protocol_spacetime_publication:attach(P, BadTrace, B)).

%% An unsupported native control encoding changes neither records nor unknown ancestry.
-spec unsupported_plan_test() -> ok.
unsupported_plan_test() ->
    P = (plan([source(0, 1, [1])], [], []))#{unsupported := [#{kind => publisher, source => 0}]},
    {T, B} = fixture(P, [#{}], []),
    ?assertMatch(#{bundle := B, publication := #{refinements := [], unsupported := [_]}},
        xls_protocol_spacetime_publication:attach(P, T, B)).

%% Synthetic plans use exact trace IDs; production plans derive them from checked source and native tuples.
-spec plan([map()], [map()], [map()]) -> map().
plan(Sources, Slots, Endpoints) ->
    #{schema => 1, sources => Sources, slots => Slots, endpoints => Endpoints,
        advance => <<"advance">>, signals => [], unsupported => [], source_files => #{}}.

%% Every fixture source has one recipient with a configurable ordered sequence mask.
-spec source(non_neg_integer(), pos_integer(), [non_neg_integer()]) -> map().
source(I, Slots, Masks) ->
    N = integer_to_binary(I), Prefix = <<"source/", N/binary>>,
    #{index => I, slots => Slots, outputs => 1, masks => Masks,
        pending => reg(<<Prefix/binary, "/pending">>, Slots), busy => reg(<<Prefix/binary, "/busy">>, 1),
        accept => <<Prefix/binary, "/accept">>}.

%% Endpoint order is the declared producer order, not inferred from actor or payload sorting.
-spec endpoint(non_neg_integer(), [non_neg_integer()]) -> map().
endpoint(I, Sources) ->
    N = integer_to_binary(I), Prefix = <<"arb/", N/binary>>,
    {C, H, O} = case length(Sources) of
        1 -> {none, none, none};
        _ -> {reg(<<Prefix/binary, "/cursor">>, 1), reg(<<Prefix/binary, "/held">>, 1), reg(<<Prefix/binary, "/owner">>, 1)}
    end,
    #{index => I, route => I, members => [#{source => S, output => 0} || S <- Sources],
        valid => <<"endpoint/", N/binary, "/valid">>, ready => <<"endpoint/", N/binary, "/ready">>,
        cursor => C, held => H, owner => O}.

%% Q/D/enable triples expose the effective next-state without requiring value changes.
-spec reg(binary(), pos_integer()) -> map().
reg(Name, Width) ->
    #{q => <<Name/binary, "/q">>, d => <<Name/binary, "/d">>, enable => <<Name/binary, "/enable">>,
        resource => <<"register/", Name/binary>>, width => Width}.

%% Sample one enabled register even when its old and new data are equal.
-spec sample_reg(binary(), non_neg_integer(), non_neg_integer()) -> map().
sample_reg(Name, Old, New) ->
    #{<<Name/binary, "/q">> => Old, <<Name/binary, "/d">> => New, <<Name/binary, "/enable">> => 1}.

%% Publisher busy is the nonempty pending invariant; acceptance remains a separate observed control.
-spec publisher(non_neg_integer(), non_neg_integer(), non_neg_integer(), 0 | 1) -> map().
publisher(I, Old, New, Accept) ->
    N = integer_to_binary(I), Prefix = <<"source/", N/binary>>,
    merge([sample_reg(<<Prefix/binary, "/pending">>, Old, New),
        sample_reg(<<Prefix/binary, "/busy">>, bit(Old =/= 0), bit(New =/= 0)),
        #{<<Prefix/binary, "/accept">> => Accept}]).

%% Ready may differ independently at each endpoint while valid follows the current publication.
-spec port(non_neg_integer(), 0 | 1, 0 | 1) -> map().
port(I, Valid, Ready) ->
    N = integer_to_binary(I), #{<<"endpoint/", N/binary, "/valid">> => Valid,
        <<"endpoint/", N/binary, "/ready">> => Ready}.

%% Arbitration state is recorded independently from the offered source data.
-spec arbiter(non_neg_integer(), {integer(), integer(), integer()}, {integer(), integer(), integer()}) -> map().
arbiter(I, {C, H, O}, {NC, NH, NO}) ->
    N = integer_to_binary(I), Prefix = <<"arb/", N/binary>>,
    merge([sample_reg(<<Prefix/binary, "/cursor">>, C, NC), sample_reg(<<Prefix/binary, "/held">>, H, NH),
        sample_reg(<<Prefix/binary, "/owner">>, O, NO)]).

%% The fixture graph's publication operation retains the original actor identity.
-spec pub(binary(), non_neg_integer(), non_neg_integer()) -> map().
pub(Id, Cycle, Source) -> event(Id, Cycle, <<"actor/", (integer_to_binary(Source))/binary>>, <<"publication_accept">>).

%% A boundary operation names its declared route, with no payload-derived identifier.
-spec transfer(binary(), non_neg_integer(), non_neg_integer()) -> map().
transfer(Id, Cycle, Route) -> event(Id, Cycle, <<"stream/route/", (integer_to_binary(Route))/binary>>, <<"boundary_transfer">>).

%% Every operation begins with an unresolved transient input and a distinct transient output.
-spec event(binary(), non_neg_integer(), binary(), binary()) -> map().
event(Id, Cycle, Actor, Operation) ->
    #{id => Id, cycle => Cycle, observer => <<"fixture">>, incarnation => <<"reset/0">>,
        actor => Actor, operation => Operation, task => <<"fixture">>, activation => Id,
        inputs => [<<Id/binary, "/in">>], outputs => [<<Id/binary, "/out">>], evidence => <<"Synthetic recorded operation">>}.

%% Construct complete tiny traces and generic graph declarations; no simulator is invoked here.
-spec fixture(map(), [map()], [map()]) -> {map(), map()}.
fixture(Plan, Rows, Events0) ->
    Defaults = defaults(Plan),
    Names = lists:usort(maps:keys(Defaults) ++ lists:append([maps:keys(R) || R <- Rows])),
    Signals = [#{id => Name, width => 32, path => <<"synthetic">>} || Name <- Names],
    N = length(Rows),
    Trace = #{signals => Signals, spans => [#{first => C, count => 1,
        values => [maps:get(Name, maps:merge(Defaults, R), 0) || Name <- Names]} || {C, R} <- lists:enumerate(0, Rows)],
        end_cycle => N, complete => true},
    Events = [E#{sequence => Seq} || {Seq, E} <- lists:enumerate(0, Events0)],
    Versions = lists:append([[#{id => V, incarnation => Inc, producer => Producer, origin => Origin,
        storage => null, evidence => <<"Synthetic version">>} || {V, Producer, Origin} <-
            [{<<Id/binary, "/in">>, root, unknown}, {<<Id/binary, "/out">>, Id, event}]]
        || #{id := Id, incarnation := Inc} <- Events]),
    ResetStarts = [C || {C, R} <- lists:enumerate(0, Rows), C > 0, maps:get(<<"reset">>, R, 0) =:= 1,
        maps:get(<<"reset">>, lists:nth(C, Rows), 0) =:= 0],
    Starts = [0 | ResetStarts],
    Epochs = [#{id => <<"reset/", (integer_to_binary(I))/binary>>, first_cycle => First, end_cycle => End}
        || {I, {First, End}} <- lists:enumerate(0, lists:zip(Starts, ResetStarts ++ [N]))],
    Bundle = #{format => spacetime, schema => 1, unit => cycle, evidence => synthetic_fixture,
        build => #{source => <<"synthetic">>, rtl => <<"synthetic">>,
            observation => <<"synthetic">>, implementation => <<"synthetic-implementation">>},
        capture => #{device => <<"fixture">>, clock => <<"clk">>, first_cycle => 0, end_cycle => N,
            complete => true, evidence => <<"Synthetic control histories">>, incarnations => Epochs,
            observers => [#{id => <<"fixture">>, first_sequence => 0, next_sequence => length(Events),
                gaps => [], scope => <<"All synthetic operation records">>}]},
        resources => [], events => Events, versions => Versions, relations => [], activity => [], physical => null},
    {Trace, Bundle}.

%% Missing row controls are inactive; all declared register and handshake fields remain present.
-spec defaults(map()) -> map().
defaults(#{sources := Sources, slots := Slots, endpoints := Endpoints}) ->
    Registers = [R || S <- Sources, K <- [pending, busy], R <- [maps:get(K, S)]] ++
        [R || S <- Slots, K <- [owner, payload], R <- [maps:get(K, S)], R =/= none] ++
        [R || E <- Endpoints, K <- [cursor, held, owner], R <- [maps:get(K, E)], R =/= none],
    Names = [Name || R <- Registers, K <- [q, d, enable], Name <- [maps:get(K, R)]] ++
        [maps:get(accept, S) || S <- Sources] ++
        [maps:get(K, E) || E <- Endpoints, K <- [valid, ready]],
    (maps:from_list([{Name, 0} || Name <- Names]))#{<<"reset">> => 0, <<"advance">> => 1}.

%% Later fragments override earlier fields when constructing one sampled edge.
-spec merge([map()]) -> map().
merge(Maps) -> lists:foldl(fun maps:merge/2, #{}, lists:reverse(Maps)).

%% Locate one retained generic version for identity assertions.
-spec version(binary(), map()) -> map().
version(Id, #{versions := Versions}) ->
    [V] = [V || V = #{id := I} <- Versions, I =:= Id], V.

%% Hand-authored Boolean controls use the same numeric trace representation as native capture.
-spec bit(boolean()) -> 0 | 1.
bit(false) -> 0;
bit(true) -> 1.
