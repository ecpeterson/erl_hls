-module(hls_fpga_supervisor_otp_tests).
-moduledoc "Finite native OTP reference for the autonomous FPGA supervisor witness. Real source counter/relay actors establish restart choices and public outcomes; ERTS scheduling is not a clock-equivalence oracle.".
-include_lib("eunit/include/eunit.hrl").

%% Standalone evidence entry used by the serial integration driver.
-export([run/1]).

-doc "Runs intensity exhaustion, expiry and explicit shutdown with an unaffected third domain. A fresh directory retains incarnation stores and the successful public outcome summary.".
-spec run(file:filename()) -> map().
run(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "result.json")),
    Exhaustion = runtime(filename:join(Stage, "exhaustion"), fun exhaustion/1),
    Expiry = runtime(filename:join(Stage, "expiry"), fun expiry/1),
    Result = #{passed => true, evidence => finite_native_otp_witness,
        source_modules => [hls_domain_counter, hls_domain_relay],
        exhaustion => Exhaustion, expiry => Expiry},
    ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result), [exclusive]),
    Result.

%% A real wall-clock expiry is deliberately exercised once, not replaced by private supervisor mutation.
-spec native_reference_test_() -> term().
native_reference_test_() ->
    {timeout, 30, fun() ->
        Stage = filename:join("_build", "fpga-supervisor-otp-" ++
            integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
            integer_to_list(erlang:unique_integer([positive]))),
        #{passed := true} = run(Stage)
    end}.

%% Each domain owns the same source topology; only the supervisor's a,b membership differs.
-spec runtime(file:filename(), fun((pid()) -> map())) -> map().
runtime(Stage, Exercise) ->
    ok = filelib:ensure_dir(filename:join(Stage, "incarnations")),
    Spec = #{actors => #{counter => #{module => hls_domain_counter, mailbox_capacity => 4},
        relay => #{module => hls_domain_relay, mailbox_capacity => 2}},
        routes => #{counter => #{out => {actor, relay}},
            relay => #{out => {external, self()}}}},
    Backends = maps:from_list([begin
        {ok, Backend} = hls_domain_erts:start_link(Spec), unlink(Backend), {Domain, Backend}
    end || Domain <- [a, b, c]]),
    try
        Store = filename:join(Stage, "incarnations"),
        ok = hls_domain_ids:create(Store),
        {ok, Owner} = hls_domain:start_link(#{a => automatic, b => automatic, c => manual},
            #{module => hls_domain_erts, endpoints => Backends, incarnation_file => Store}),
        unlink(Owner),
        try Exercise(Owner) after catch gen_server:stop(Owner) end
    after [catch gen_server:stop(P) || P <- maps:values(Backends)] end.

%% Two restart attempts succeed; the third failure exhausts OTP's shared subtree intensity.
-spec exhaustion(pid()) -> map().
exhaustion(Owner) ->
    {HC, C} = independent(Owner),
    {ok, Sup} = hls_fpga_supervisor_otp:start_link(Owner,
        #{strategy => one_for_one, intensity => 2, period => 60}),
    unlink(Sup),
    try
        {HA0, A0} = child(Sup, Owner, a, none),
        {HB, B} = child(Sup, Owner, b, none),
        0 = read(A0), 7 = add(B, 7),
        fail(A0),
        {HA1, A1} = child(Sup, Owner, a, HA0),
        true = A1 =/= A0, 0 = read(A1), unchanged(Owner, b, HB, B, 7),
        unchanged(Owner, c, HC, C, 23),
        fail(A1),
        {HA2, A2} = child(Sup, Owner, a, HA1),
        true = A2 =/= A1, 0 = read(A2), unchanged(Owner, b, HB, B, 7),
        unchanged(Owner, c, HC, C, 23),
        SupMonitor = monitor(process, Sup), BMonitor = monitor(process, B),
        fail(A2),
        shutdown = down(SupMonitor, Sup), shutdown = down(BMonitor, B),
        stopped(Owner, a, HA2), stopped(Owner, b, HB),
        unchanged(Owner, c, HC, C, 23),
        #{initial_and_restarted_values => [0, 0, 0], successful_restarts => 2,
            next_failure_stops_subtree => true, sibling_unchanged_before_exhaustion => true,
            outside_domain_unchanged => true, fresh_pid_and_incarnation => true}
    after catch gen_server:stop(Sup, shutdown, 10000) end.

%% Expired restarts leave the window; explicit parent shutdown still retires both healthy children.
-spec expiry(pid()) -> map().
expiry(Owner) ->
    {HC, C} = independent(Owner),
    {ok, Sup} = hls_fpga_supervisor_otp:start_link(Owner,
        #{strategy => one_for_one, intensity => 2, period => 1}),
    unlink(Sup),
    try
        {HA0, A0} = child(Sup, Owner, a, none),
        {HB, B} = child(Sup, Owner, b, none),
        7 = add(B, 7),
        fail(A0), {HA1, A1} = child(Sup, Owner, a, HA0),
        fail(A1), {HA2, A2} = child(Sup, Owner, a, HA1),
        %% OTP records whole-second monotonic times; two seconds clears a one-second window.
        receive after 2100 -> ok end,
        fail(A2), {HA3, A3} = child(Sup, Owner, a, HA2),
        0 = read(A3), true = is_process_alive(Sup),
        unchanged(Owner, b, HB, B, 7), unchanged(Owner, c, HC, C, 23),
        AMonitor = monitor(process, A3), BMonitor = monitor(process, B),
        ok = gen_server:stop(Sup, shutdown, 10000),
        shutdown = down(AMonitor, A3), shutdown = down(BMonitor, B),
        stopped(Owner, a, HA3), stopped(Owner, b, HB),
        unchanged(Owner, c, HC, C, 23),
        #{restart_after_expiry => true, explicit_shutdown_stops_children => true,
            outside_domain_unchanged => true, sibling_unchanged_before_shutdown => true}
    after catch gen_server:stop(Sup, shutdown, 10000) end.

%% Domain c remains outside both ordinary OTP supervisor instances.
-spec independent(pid()) -> {hls_domain:handle(), pid()}.
independent(Owner) ->
    {ok, _} = hls_domain:activate(Owner, c),
    {Handle, Counter} = ready(Owner, c),
    23 = add(Counter, 23),
    {Handle, Counter}.

%% Wait for the representative and its actual source incarnation, never just a newly spawned child PID.
-spec child(pid(), pid(), atom(), none | hls_domain:handle()) -> {hls_domain:handle(), pid()}.
child(Sup, Owner, Domain, Previous) ->
    wait(fun() ->
        case lists:keyfind(Domain, 1, supervisor:which_children(Sup)) of
            {Domain, Pid, worker, _} when is_pid(Pid) ->
                try hls_domain_instance:status(Pid) of
                    #{phase := ready, handle := Handle} when Handle =/= Previous ->
                        case hls_domain:resolve(Owner, Handle, counter) of
                            {ok, Counter} -> {ok, {Handle, Counter}};
                            _ -> wait
                        end;
                    _ -> wait
                catch exit:_ -> wait end;
            _ -> wait
        end
    end).

%% Observe an existing domain without granting the observer replacement authority.
-spec ready(pid(), atom()) -> {hls_domain:handle(), pid()}.
ready(Owner, Domain) ->
    wait(fun() ->
        case hls_domain:status(Owner, Domain) of
            {ok, #{phase := ready, handle := Handle}} ->
                {ok, Counter} = hls_domain:resolve(Owner, Handle, counter),
                {ok, {Handle, Counter}};
            _ -> wait
        end
    end).

%% Identity and committed source state both survive another domain's restart.
-spec unchanged(pid(), atom(), hls_domain:handle(), pid(), non_neg_integer()) -> ok.
unchanged(Owner, Domain, Handle, Counter, Value) ->
    {Handle, Counter} = ready(Owner, Domain), Value = read(Counter), ok.

%% Acknowledged shutdown must retain exactly the incarnation that was retired.
-spec stopped(pid(), atom(), hls_domain:handle()) -> ok.
stopped(Owner, Domain, Handle) ->
    wait(fun() ->
        case hls_domain:status(Owner, Domain) of
            {ok, #{phase := stopped, handle := Handle}} -> {ok, ok};
            _ -> wait
        end
    end).

%% Public source messages carry request IDs, matching the generated counter/relay boundary.
-spec add(pid(), non_neg_integer()) -> non_neg_integer().
add(Counter, Value) -> request(Counter, add, Value).

%% Reading is an ordinary source input, not private-state introspection.
-spec read(pid()) -> non_neg_integer().
read(Counter) -> request(Counter, read, 0).

%% Correlation excludes unrelated reports from earlier actors or fixture phases.
-spec request(pid(), add | read, non_neg_integer()) -> non_neg_integer().
request(Counter, Kind, Value) ->
    Id = erlang:unique_integer([positive]) band ((1 bsl 32) - 1),
    ok = hls_statem:admit_cast(Counter, {Kind, Id, Value}),
    receive {'$gen_cast', {value, Id, Result}} -> Result
        after 5000 -> error({missing_source_report, Kind, Id}) end.

%% Establish publishing/nonzero state so the actual source assertion reliably fails.
-spec fail(pid()) -> ok.
fail(Counter) ->
    Value = add(Counter, 1), true = Value > 0,
    Monitor = monitor(process, Counter),
    _ = catch hls_statem:admit_cast(Counter, {explode, 0, 0}),
    Reason = down(Monitor, Counter), true = Reason =/= normal, true = Reason =/= shutdown,
    ok.

%% Only this monitor's actual terminal signal establishes process death.
-spec down(reference(), pid()) -> term().
down(Monitor, Pid) ->
    receive {'DOWN', Monitor, process, Pid, Reason} -> Reason
        after 10000 -> error({missing_down, Pid}) end.

%% A wall-clock observation deadline is a test bound, never a synthetic reset completion.
-spec wait(fun(() -> {ok, Result} | wait)) -> Result.
wait(Fun) -> wait(Fun, erlang:monotonic_time(millisecond) + 10000).

%% Retain asynchronous failures rather than accepting elapsed time as lifecycle evidence.
-spec wait(fun(() -> {ok, Result} | wait), integer()) -> Result.
wait(Fun, Deadline) ->
    case Fun() of
        {ok, Result} -> Result;
        wait ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> wait(Fun, Deadline) end
    end.
