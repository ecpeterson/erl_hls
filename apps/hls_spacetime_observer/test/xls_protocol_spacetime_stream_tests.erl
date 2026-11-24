-module(xls_protocol_spacetime_stream_tests).
-include_lib("eunit/include/eunit.hrl").

%% Synthetic FIFO witnesses use arbitrary endpoints and payloads, not a decoder workload.
-spec simultaneous_equal_frames_test() -> ok.
simultaneous_equal_frames_test() ->
    A = frame(7),
    Rows = [maps:merge(accept(0, A), accept(1, A)), accept(0, A)] ++
        output(9, A) ++ output(8, A) ++ output(8, A),
    B = capture(Rows),
    #{stream := #{frames := [Other, First, Second], pending := []}, bundle := #{events := Events}} = B,
    ?assertEqual([route(9), route(8), route(8)], [maps:get(route, F) || F <- [Other, First, Second]]),
    ?assertEqual([0, 0, 1], [maps:get(ordinal, F) || F <- [Other, First, Second]]),
    ?assertNotEqual(maps:get(transfer, First), maps:get(transfer, Second)),
    ?assertEqual(maps:get(words, First), maps:get(words, Second)),
    [Producer] = [E || E = #{id := Id} <- Events, Id =:= maps:get(transfer, Second)],
    [Consumer] = [E || E = #{id := Id} <- Events, Id =:= maps:get(event, Second)],
    ?assertEqual(maps:get(outputs, Producer), maps:get(inputs, Consumer)).

%% Offers may change under stall; only accepted input and output edges create occurrences.
-spec independent_stalls_test() -> ok.
independent_stalls_test() ->
    A = frame(7),
    Stalled = (accept(0, frame(99)))#{<<"stream/event/0/ready">> := 0},
    [Route, Header, Payload] = output(8, A),
    B = capture([Stalled, accept(0, A), Route,
        Header#{<<"output_ready">> := 0}, Header, #{}, Payload]),
    #{stream := #{frames := [F], pending := []}, bundle := #{events := Events}} = B,
    ?assertEqual(6, maps:get(cycle, F)),
    ?assertEqual(2, maps:get(first_cycle, F)),
    ?assertEqual(2, length(Events)).

%% Completed control frames have route occurrences but no invented endpoint admission.
-spec management_frames_test() -> ok.
management_frames_test() ->
    #{stream := #{frames := [A, B]}} = capture(output(7, frame(0)) ++ output(7, frame(0))),
    ?assertEqual([0, 1], [maps:get(ordinal, F) || F <- [A, B]]),
    ?assertEqual([null, null], [maps:get(transfer, F) || F <- [A, B]]).

%% An accepted tail is disclosed without claiming the finite capture drained the gateway.
-spec pending_tail_test() -> ok.
pending_tail_test() ->
    A = frame(42),
    [Route, Header | _] = output(8, A),
    #{stream := #{frames := [], pending := [Pending], partial := Partial}} =
        capture([accept(0, A), Route, Header]),
    ?assertEqual([route(8), 1, 42], maps:get(words, Pending)),
    ?assertEqual([route(8), 1], maps:get(words, Partial)),
    ?assertEqual(1, maps:get(remaining, Partial)).

%% Reset retires partial serialization and queued occurrences; identical later frames are new identities.
-spec reset_retires_pending_test() -> ok.
reset_retires_pending_test() ->
    A = frame(7),
    [Route | _] = output(8, A),
    Rows = [accept(0, A), Route, #{<<"reset">> => 1}, #{<<"reset">> => 1}, accept(0, A)] ++ output(8, A),
    {P, T, B} = fixture(Rows),
    C = maps:get(capture, B),
    Epochs = [#{id => <<"reset/0">>, first_cycle => 0, end_cycle => 2},
        #{id => <<"reset/1">>, first_cycle => 2, end_cycle => 8}],
    Joined = xls_protocol_spacetime_stream:attach(P, T, B#{capture := C#{incarnations := Epochs}}),
    _ = hls_spacetime:validate(maps:get(bundle, Joined)),
    #{stream := #{frames := [New], retired := [#{pending := [Old], partial := Partial}], pending := []}} = Joined,
    ?assertEqual(<<"reset/1">>, maps:get(incarnation, New)),
    ?assertEqual(0, maps:get(ordinal, New)),
    ?assertNotEqual(maps:get(event, Old), maps:get(transfer, New)),
    ?assertEqual([route(8)], maps:get(words, Partial)).

%% A complete public packet cannot borrow a pre-reset admission.
-spec no_cross_reset_join_test() -> ok.
no_cross_reset_join_test() ->
    A = frame(7),
    {P, T, B} = fixture([accept(0, A), #{<<"reset">> => 1}] ++ output(8, A)),
    Route8 = route(8),
    ?assertError({spacetime_stream, {missing_admission, Route8, 0}},
        xls_protocol_spacetime_stream:attach(P, T, B)).

%% Missing input, changed payload, per-route reordering and malformed final markers all reject.
-spec contradictory_output_test() -> ok.
contradictory_output_test() ->
    A = frame(7), B = frame(8),
    Route8 = route(8),
    ?assertError({spacetime_stream, {missing_admission, Route8, 0}}, capture(output(8, A))),
    ?assertException(error, {spacetime_stream, {frame_mismatch, _, _, _}},
        capture([accept(0, A)] ++ output(8, B))),
    ?assertException(error, {spacetime_stream, {frame_mismatch, _, _, _}},
        capture([accept(0, A), accept(0, B)] ++ output(8, B) ++ output(8, A))),
    Route10 = route(10),
    ?assertError({spacetime_stream, {unknown_route, Route10}}, capture(output(10, A))),
    [R, H, D] = output(8, A),
    ?assertError({spacetime_stream, route_last}, capture([R#{<<"output_last">> := 1}])),
    ?assertError({spacetime_stream, header_last}, capture([R, H#{<<"output_last">> := 1}])),
    ?assertError({spacetime_stream, payload_last}, capture([R, H, D#{<<"output_last">> := 0}])).

%% A final-word match cannot borrow a frame admitted after its route word was already emitted.
-spec admission_after_output_test() -> ok.
admission_after_output_test() ->
    A = frame(7),
    [Route, Header, Payload] = output(8, A),
    ?assertException(error, {spacetime_stream, {admission_after_output, _, 1, 0}},
        capture([Route, maps:merge(Header, accept(0, A)), Payload])).

%% Appending stream observation does not reallocate existing event, version or resource IDs.
-spec preserves_prior_graph_test() -> ok.
preserves_prior_graph_test() ->
    {P, T, B} = fixture([accept(0, frame(7))]),
    Prior = B#{events := [#{id => <<"prior/event">>}], versions := [#{id => <<"prior/value">>}],
        resources := [#{id => <<"prior/resource">>}]},
    #{bundle := Joined} = xls_protocol_spacetime_stream:attach(P, T, Prior),
    ?assertEqual(#{id => <<"prior/event">>}, hd(maps:get(events, Joined))),
    ?assertEqual(#{id => <<"prior/value">>}, hd(maps:get(versions, Joined))),
    ?assertEqual(#{id => <<"prior/resource">>}, hd(maps:get(resources, Joined))).

%% Exact regenerated bindings, rather than a familiar basename, establish the observed boundary.
-spec source_binding_test() -> ok.
source_binding_test() ->
    Files = source_fixture(),
    #{signals := Signals, endpoints := [A, B]} = xls_protocol_spacetime_stream:plan(Files),
    ?assertEqual(6, length(Signals)),
    ?assertEqual([route(8), route(9)], [maps:get(route, E) || E <- [A, B]]),
    lists:foreach(fun(Name) ->
        Changed = Files#{Name := <<(maps:get(Name, Files))/binary, "\n// changed\n">>},
        ?assertError({spacetime_stream_source, Name}, xls_protocol_spacetime_stream:plan(Changed))
    end, [<<"application/protocol_application_top.sv">>, <<"application/application_config.x">>,
        <<"application/gateway.x">>, <<"support/target/xls/hls_partition_io.x">>,
        <<"support/target/xls/lib/protocol_framing.x">>, <<"actors/frame_config.x">>]).

%% A new gateway selector cannot inherit the ordered-gateway interpretation accidentally.
-spec unsupported_gateway_test() -> ok.
unsupported_gateway_test() ->
    Files = source_fixture(),
    Deployment = #{devices := #{fixture := Binding = #{control_adapter := Adapter}}} =
        binary_to_term(maps:get(<<"application-build.etf">>, Files)),
    Source = <<"xls/templates/another_gateway.x">>,
    Changed = Deployment#{devices := #{fixture => Binding#{control_adapter :=
        Adapter#{gateway_source := Source}}}},
    ?assertError({spacetime_stream, {unsupported_gateway, Source}},
        xls_protocol_spacetime_stream:plan(
            Files#{<<"application-build.etf">> := term_to_binary(Changed)}
        )).

%% A self-contained synthetic deployment uses the real mechanical emitter, without invoking XLS.
-spec source_fixture() -> map().
source_fixture() ->
    Layout = hls_frame_layout:new(3),
    Binding = #{host => 1, control => 7, identity => <<0:256>>, events => #{
        8 => #{port => "external_0"}, 9 => #{port => "external_1"}},
        control_adapter => #{input_bits => 194, command_bits => 195,
            activation_module => "hls_partition_activation", gateway_source => "xls/templates/protocol_application.x"}},
    Boundary = #{inspection => none, activation => explicit_start, frame_layout => Layout,
        externals => [#{index => 0}, #{index => 1}], outputs => []},
    Gateway = xls_protocol_application:emit(Binding),
    Files = maps:from_list([{iolist_to_binary(["application/", N]), iolist_to_binary(B)} ||
        {N, B} <- maps:to_list(Gateway)]),
    Libraries = [{hls_target, <<"support/target/">>, "xls/hls_partition_io.x"},
        {hls_target, <<"support/target/">>, "xls/lib/protocol_framing.x"},
        {hls_compile, <<"support/compiler/">>, "xls/lib/axis.x"}],
    Support = maps:from_list([begin
        {ok, Bytes} = file:read_file(filename:join(code:priv_dir(App), Name)),
        {iolist_to_binary([Prefix, Name]), Bytes}
    end || {App, Prefix, Name} <- Libraries]),
    (maps:merge(Files, Support))#{
        <<"application-build.etf">> => term_to_binary(#{
            devices => #{fixture => Binding}, source_boundary => Boundary
        }),
        <<"application/protocol_application_top.sv">> => iolist_to_binary(sv_protocol_application:emit(Binding, Boundary)),
        <<"actors/frame_config.x">> => iolist_to_binary(xls_frame_layout:config(Layout))}.

%% Generic validation checks that transfer dependencies are ordinary well-formed graph edges.
-spec capture([map()]) -> map().
capture(Rows) ->
    {P, T, B} = fixture(Rows),
    Joined = #{bundle := Graph} = xls_protocol_spacetime_stream:attach(P, T, B),
    _ = hls_spacetime:validate(Graph),
    ?assertNot(maps:is_key(stream, Graph)),
    ?assert(lists:all(fun(E) -> not maps:is_key(stream, E) end, maps:get(events, Graph))),
    Joined.

%% Minimal checked-trace shape; rows are hand-authored synthetic samples.
-spec fixture([map()]) -> {map(), map(), map()}.
fixture(Rows) ->
    Endpoints = [#{index => I, endpoint => I + 8, route => route(I + 8),
        data => tap(I, <<"data">>), valid => tap(I, <<"valid">>), ready => tap(I, <<"ready">>)} || I <- [0, 1]],
    Signals = [#{id => N, width => W, path => <<"synthetic">>} || {N, W} <-
        [{<<"reset">>, 1}, {<<"output_valid">>, 1}, {<<"output_ready">>, 1},
         {<<"output_data">>, 32}, {<<"output_last">>, 1}] ++
        [{tap(I, F), W} || I <- [0, 1], {F, W} <- [{<<"data">>, 128}, {<<"valid">>, 1}, {<<"ready">>, 1}]]],
    N = length(Rows),
    Trace = #{signals => Signals, spans => [#{first => C, count => 1,
        values => [maps:get(maps:get(id, Sig), Row, 0) || Sig <- Signals]} || {C, Row} <- lists:enumerate(0, Rows)],
        end_cycle => N, complete => true},
    Plan = #{endpoints => Endpoints, host => 1, control => 7, payload_words => 3,
        signals => [], source_files => #{}},
    Bundle = #{format => spacetime, schema => 1, unit => cycle, evidence => synthetic_fixture,
        build => #{source => <<"synthetic">>, rtl => <<"synthetic">>,
            observation => <<"synthetic">>, implementation => <<"synthetic-implementation">>},
        capture => #{device => <<"board">>, clock => <<"clk">>, first_cycle => 0,
            end_cycle => N, complete => true, evidence => <<"Synthetic stream parser fixture">>,
            incarnations => [#{id => <<"reset/0">>, first_cycle => 0, end_cycle => N}], observers => []},
        resources => [], events => [], versions => [], relations => [], activity => [], physical => null},
    {Plan, Trace, Bundle}.

%% The numeric header carries one payload word; the body starts after the header.
-spec frame(non_neg_integer()) -> non_neg_integer().
frame(Payload) -> (Payload bsl 32) bor 1.

%% Endpoints occupy the high half-word, destination host the low half-word.
-spec route(non_neg_integer()) -> non_neg_integer().
route(Endpoint) -> (Endpoint bsl 16) bor 1.

%% Semantic tap IDs mirror the qualified planner, with no dependency on trace column order.
-spec tap(non_neg_integer(), binary()) -> binary().
tap(I, Field) -> <<"stream/event/", (integer_to_binary(I))/binary, "/", Field/binary>>.

%% One admitted endpoint frame; unspecified fields are inactive.
-spec accept(non_neg_integer(), non_neg_integer()) -> map().
accept(I, Data) -> #{tap(I, <<"data">>) => Data, tap(I, <<"valid">>) => 1, tap(I, <<"ready">>) => 1}.

%% Three accepted words form one ordinary one-word-payload public frame.
-spec output(non_neg_integer(), non_neg_integer()) -> [map()].
output(Endpoint, Raw) ->
    [#{<<"output_valid">> => 1, <<"output_ready">> => 1, <<"output_data">> => Word,
        <<"output_last">> => Last} || {Word, Last} <- [{route(Endpoint), 0},
            {Raw band ((1 bsl 32) - 1), 0}, {Raw bsr 32, 1}]].
