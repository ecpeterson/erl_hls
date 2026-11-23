-module(hls_node_requests_tests).
-moduledoc "Admission/completion ownership witnesses shared by managed actors and legacy wire channels.".
-include_lib("eunit/include/eunit.hrl").

%% Admission releases peer credit exactly once while retained calls still consume target completion slots.
-spec admission_completion_test() -> ok.
admission_completion_test() ->
    Target = self(), Group = {domain, Target},
    {A, S1} = hls_node_requests:enqueue(Group, Target, {call, {self(), make_ref()}, read}, hls_node_requests:new()),
    {B, S2} = hls_node_requests:enqueue(Group, Target, {cast, none, release}, S1),
    S3 = hls_node_requests:submit(A, S2),
    ?assertEqual(none, hls_node_requests:head(Group, S3)),
    S4 = hls_node_requests:admit(A, S3),
    ?assertEqual(S4, hls_node_requests:admit(A, S4)),
    ?assertEqual(S4, hls_node_requests:retry(A, S4)),
    ?assertEqual(1, hls_node_requests:waiting(S4)),
    ?assertEqual(1, hls_node_requests:calls(Target, S4)),
    ?assertMatch({B, #{operation := {cast, none, release}}}, hls_node_requests:head(Group, S4)),
    {#{phase := admitted}, S5} = hls_node_requests:finish(A, S4),
    ?assertEqual(0, hls_node_requests:calls(Target, S5)),
    {_, S6} = hls_node_requests:finish(B, S5),
    ?assertEqual([], hls_node_requests:groups(S6)),
    ?assertEqual({none, S6}, hls_node_requests:finish(A, S6)), ok.

%% Proven-unsent retries preserve a shared physical channel's original order and credit.
-spec retry_order_test() -> ok.
retry_order_test() ->
    Group = {application, 7},
    {A, S1} = hls_node_requests:enqueue(Group, self(), {cast, none, first}, hls_node_requests:new()),
    {B, S2} = hls_node_requests:enqueue(Group, self(), {cast, none, second}, S1),
    S3 = hls_node_requests:submit(A, S2),
    S4 = hls_node_requests:retry(A, S3),
    ?assertEqual(2, hls_node_requests:waiting(S4)),
    ?assertMatch({A, #{operation := {cast, none, first}}}, hls_node_requests:head(Group, S4)),
    S5 = hls_node_requests:admit(A, hls_node_requests:submit(A, S4)),
    ?assertMatch({B, _}, hls_node_requests:head(Group, S5)), ok.

%% A physical reply may precede the broker's write acknowledgement without leaking admission credit.
-spec early_completion_test() -> ok.
early_completion_test() ->
    {Token, S1} = hls_node_requests:enqueue({debug, 1}, self(), {call, {self(), make_ref()}, read}, hls_node_requests:new()),
    S2 = hls_node_requests:submit(Token, S1),
    {#{phase := submitting}, S3} = hls_node_requests:finish(Token, S2),
    ?assertEqual(0, hls_node_requests:waiting(S3)),
    ?assertEqual(0, hls_node_requests:calls(self(), S3)),
    ?assertEqual(S3, hls_node_requests:admit(Token, S3)), ok.

%% Retiring one target cannot erase another target's interleaved legacy operation.
-spec target_retirement_test() -> ok.
target_retirement_test() ->
    Other = spawn(fun() -> receive stop -> ok end end),
    try
        Group = {application, 7},
        {A, S1} = hls_node_requests:enqueue(Group, self(), {cast, none, first}, hls_node_requests:new()),
        {B, S2} = hls_node_requests:enqueue(Group, Other, {cast, none, second}, S1),
        S3 = hls_node_requests:remove_target(self(), hls_node_requests:submit(A, S2)),
        ?assertEqual(error, hls_node_requests:find(A, S3)),
        ?assertEqual(1, hls_node_requests:waiting(S3)),
        ?assertMatch({B, #{target := Other}}, hls_node_requests:head(Group, S3))
    after Other ! stop end, ok.
