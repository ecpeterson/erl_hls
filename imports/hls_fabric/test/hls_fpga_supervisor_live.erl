-module(hls_fpga_supervisor_live).
-moduledoc "Finite mixed-placement witness: an ordinary host supervisor owns a compiled FPGA supervisor, whose two source domains restart independently with no host policy traffic.".
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-export([run/4]).

-doc "Checks public generated-RTL behavior and ordinary host lifecycle APIs against the retained native OTP outcomes. No private RTL state or routed hardware is observed.".
-spec run(file:filename(), file:filename(), file:filename(), file:filename()) -> ok.
run(Binary, Interface, Native, Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "unused")),
    {ok, Bytes} = file:read_file(Interface), Info = binary_to_term(Bytes),
    Codecs = maps:get(codecs, Info),
    {ok, NativeBytes} = file:read_file(Native), NativeResult = json:decode(NativeBytes),
    true = maps:get(<<"passed">>, NativeResult),
    #{<<"exhaustion">> := #{<<"successful_restarts">> := 2,
        <<"next_failure_stops_subtree">> := true,
        <<"fresh_pid_and_incarnation">> := true},
      <<"expiry">> := #{<<"restart_after_expiry">> := true,
        <<"explicit_shutdown_stops_children">> := true}} = NativeResult,
    {ok, Device} = hls_fpga_supervisor_device:start_link(Binary, filename:join(Stage, "pins.log")),
    unlink(Device),
    {ok, Backend} = hls_fpga_supervisor_backend:start_link(Device, Codecs, {1, 64}), unlink(Backend),
    Store = filename:join(Stage, "incarnations.bin"), ok = hls_domain_ids:create(Store),
    {ok, Owner} = hls_domain:start_link(#{board => automatic},
        #{module => hls_fpga_supervisor_backend, endpoints => #{board => Backend}, incarnation_file => Store}),
    unlink(Owner),
    try
        {ok, {1, 64}} = hls_domain_ids:reserve(Owner, 64),
        {ok, Parent} = hls_shutdown_supervisor:start_link(one_for_one, [{board, Owner}]), unlink(Parent),
        {Representative, ParentHandle} = parent(Parent),
        Initial = pins(Device), IA = current(0, Initial), IB = current(1, Initial),
        0 = value(Device, 0, IA, 4, 1, 0),
        7 = value(Device, 0, IA, 3, 2, 7),
        23 = value(Device, 1, IB, 3, 3, 23),
        A1 = fail_and_restart(Device, 0, IA, Codecs),
        0 = value(Device, 0, A1, 4, 4, 0),
        23 = value(Device, 1, IB, 4, 5, 0),
        Stale = app(Device, 0, IA, 3, 6, 99), true = maps:get(<<"app_rejected">>, Stale),
        0 = value(Device, 0, A1, 4, 7, 0),
        {board, Epoch} = ParentHandle,
        Before = maps:get(<<"grant_next">>, pins(Device)),
        Repeat = command(Device, io_lib:format("grant ~B 1 64", [Epoch])),
        Before = maps:get(<<"grant_next">>, Repeat),
        ok = gen_server:stop(Backend, noconnection, 5000),
        wait(fun() -> case hls_domain_instance:status(Representative) of {error, noconnection} -> {ok, true}; _ -> wait end end),
        1 = value(Device, 0, A1, 3, 8, 1),
        A2 = fail_and_restart(Device, 0, A1, Codecs),
        23 = value(Device, 1, IB, 4, 9, 0),
        true = is_process_alive(Representative),
        {ok, Reattached} = hls_fpga_supervisor_backend:start_link(Device, Codecs, none), unlink(Reattached),
        {ok, _} = hls_domain:reattach(Owner, ParentHandle, Reattached),
        wait(fun() -> case hls_domain_instance:status(Representative) of
            #{phase := ready, handle := ParentHandle} -> {ok, true}; _ -> wait end end),
        A2 = current(0, pins(Device)),
        ok = supervisor:terminate_child(Parent, board),
        #{handle := ParentHandle} = phase(Owner, stopped),
        Stopped = pins(Device),
        true = child_phase(0, Stopped, Codecs) =:= stopped,
        true = child_phase(1, Stopped, Codecs) =:= stopped,
        exit(Parent, shutdown),
        %% Manual parent replacement reserves another disjoint grant before submission.
        {NextBackend, H2} = replace_parent(Owner, Reattached, Device, Codecs, 64),
        Window = window_and_exhaustion(Device, Codecs),
        #{handle := H2} = phase(Owner, failed),
        {LastBackend, H3} = replace_parent(Owner, NextBackend, Device, Codecs, 3),
        Identity = identity_exhaustion(Device, Codecs),
        #{handle := H3} = phase(Owner, failed),
        {board, LastEpoch} = H3,
        OldGrant = command(Device, io_lib:format("grant ~B 1 64", [LastEpoch + 1])),
        false = maps:get(<<"grant_accepted">>, OldGrant),
        {error, {incarnation_changed, _, _}} = hls_domain:stop(Owner, ParentHandle, 5000),
        Result = #{passed => true, host_otp_parent => true,
            independent_children => true, fresh_child_state_and_incarnation => true,
            stale_application_rejected => true, duplicate_grant_preserved_cursor => true,
            autonomous_restart_without_host_adapter => true,
            same_parent_incarnation_after_reattach => true,
            explicit_parent_shutdown_retired_children => true,
            window => Window, identity => Identity,
            stale_grant_and_parent_stop_rejected => true,
            common_native_outcomes_matched => true, native_reference => NativeResult,
            evidence => finite_public_pin_rtl_and_host_otp_witness,
            exclusions => [physical_reset, routing_timing, child_virtual_pid_retirement_order]},
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result), [exclusive]),
        gen_server:stop(LastBackend), ok
    after
        catch gen_server:stop(Owner), catch gen_server:stop(Backend),
        catch hls_fpga_supervisor_device:stop(Device)
    end.

%% The parent observer may be ready only after the actual compiled subtree is ready.
-spec parent(pid()) -> {pid(), hls_domain:handle()}.
parent(Parent) -> wait(fun() ->
    case supervisor:which_children(Parent) of
        [{board, Pid, worker, _}] when is_pid(Pid) ->
            case hls_domain_instance:status(Pid) of
                #{phase := ready, handle := Handle} -> {ok, {Pid, Handle}};
                _ -> wait
            end;
        _ -> wait
    end
end).
%% Exact phase observation never supplies an acknowledgement on the hardware's behalf.
-spec phase(pid(), hls_domain_lifecycle:phase()) -> map().
phase(Owner, Expected) -> wait(fun() -> case hls_domain:status(Owner, board) of
    {ok, #{phase := Expected} = Status} -> {ok, Status}; _ -> wait end end).
%% Reattachment retains the failed/stopped parent identity until a fresh grant starts replacement.
-spec replace_parent(pid(), pid(), pid(), map(), pos_integer()) -> {pid(), hls_domain:handle()}.
replace_parent(Owner, OldBackend, Device, Codecs, Count) ->
    {ok, #{handle := Handle}} = hls_domain:status(Owner, board),
    ok = gen_server:stop(OldBackend, noconnection, 5000),
    {ok, Grant} = hls_domain_ids:reserve(Owner, Count),
    {ok, Backend} = hls_fpga_supervisor_backend:start_link(Device, Codecs, Grant), unlink(Backend),
    {ok, _} = hls_domain:reattach(Owner, Handle, Backend),
    {ok, _} = hls_domain:replace(Owner, Handle),
    #{handle := Next} = phase(Owner, ready), {Backend, Next}.

%% Two rapid failures consume the window; aging them out permits another two, but not a third.
-spec window_and_exhaustion(pid(), map()) -> map().
window_and_exhaustion(Device, Codecs) ->
    P = pins(Device), A = current(0, P), B = current(1, P),
    23 = value(Device, 1, B, 3, 20, 23),
    1 = value(Device, 0, A, 3, 21, 1), A1 = fail_and_restart(Device, 0, A, Codecs),
    1 = value(Device, 0, A1, 3, 22, 1), A2 = fail_and_restart(Device, 0, A1, Codecs),
    _ = command(Device, "step 30000"),
    1 = value(Device, 0, A2, 3, 23, 1), A3 = fail_and_restart(Device, 0, A2, Codecs),
    1 = value(Device, 0, A3, 3, 24, 1), A4 = fail_and_restart(Device, 0, A3, Codecs),
    23 = value(Device, 1, B, 4, 25, 0),
    1 = value(Device, 0, A4, 3, 26, 1), _ = app(Device, 0, A4, 5, 27, 0),
    End = wait_parent_failed(Device, Codecs),
    true = child_phase(0, End, Codecs) =:= stopped,
    true = child_phase(1, End, Codecs) =:= stopped,
    #{window_expiry => true, two_restarts_allowed => true, third_retires_subtree => true}.
%% A three-number grant can start two children and replace one, then must fail without reuse.
-spec identity_exhaustion(pid(), map()) -> map().
identity_exhaustion(Device, Codecs) ->
    A = current(0, pins(Device)),
    1 = value(Device, 0, A, 3, 30, 1), A1 = fail_and_restart(Device, 0, A, Codecs),
    1 = value(Device, 0, A1, 3, 31, 1), _ = app(Device, 0, A1, 5, 32, 0),
    End = wait_parent_failed(Device, Codecs),
    A1 = current(0, End),
    true = child_phase(0, End, Codecs) =:= stopped,
    true = child_phase(1, End, Codecs) =:= stopped,
    #{finite_grant_exhaustion => true, no_identity_reuse => true}.
%% Only a source callback fault requests restart; the instrument cannot write controller internals.
-spec fail_and_restart(pid(), 0 | 1, pos_integer(), map()) -> pos_integer().
fail_and_restart(Device, Slot, Previous, Codecs) ->
    _ = app(Device, Slot, Previous, 5, 100 + Previous, 0),
    wait(fun() -> P = pins(Device), New = current(Slot, P),
        case New > Previous andalso child_phase(Slot, P, Codecs) =:= ready of
            true -> {ok, New}; false -> wait end end).
%% Parent failure is inspected after real child fencing; time does not substitute for it.
-spec wait_parent_failed(pid(), map()) -> map().
wait_parent_failed(Device, Codecs) -> wait(fun() -> P = pins(Device),
    case enum(phase, maps:get(<<"domain_phase">>, P), Codecs) of failed -> {ok, P}; _ -> wait end end).
%% The latest source output is an external observation, never direct access to a register.
-spec value(pid(), 0 | 1, pos_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
value(Device, Slot, Epoch, Tag, Request, Value) ->
    P = app(Device, Slot, Epoch, Tag, Request, Value),
    false = maps:get(<<"app_rejected">>, P),
    wait(fun() -> Q = pins(Device), R = maps:get(key("report_", Slot, ""), Q),
        case R of #{<<"incarnation">> := Epoch, <<"request">> := Request, <<"value">> := Result} -> {ok, Result}; _ -> wait end end).
%% Fixture selectors come from the unchanged counter source's declared message ordering.
-spec app(pid(), 0 | 1, pos_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> map().
app(Device, Slot, Epoch, Tag, Request, Value) ->
    command(Device, io_lib:format("application ~B ~B ~B ~B ~B", [Slot, Epoch, Tag, Request, Value])).
%% All snapshots include complete current parent and child public observations.
-spec pins(pid()) -> map().
pins(Device) -> command(Device, "snapshot").
%% Clock advancing is test stimulus, not host-side recovery policy.
-spec command(pid(), iodata()) -> map().
command(Device, Text) -> hls_fpga_supervisor_device:command(Device, Text).
%% Child labels select separately exposed ports rather than shared payload storage.
-spec current(0 | 1, map()) -> pos_integer().
current(Slot, P) -> maps:get(key("child_", Slot, "_domain_current"), P).
%% Atom decoding uses exactly the lifecycle's retained source descriptors.
-spec child_phase(0 | 1, map(), map()) -> hls_domain_lifecycle:phase().
child_phase(Slot, P, Codecs) -> enum(phase, maps:get(key("child_", Slot, "_domain_phase"), P), Codecs).
%% No numeric domain phase or cause values are duplicated in the host fixture.
-spec enum(atom(), non_neg_integer(), map()) -> atom().
enum(Kind, Bits, Codecs) ->
    Type = maps:get(Kind, Codecs), {Value, <<>>} = hls_type:unpack(<<Bits:(hls_type:width(Type))>>, Type), Value.
%% Stable generated names are shared by the fixed two-child witness only.
-spec key(string(), 0 | 1, string()) -> binary().
key(Prefix, Slot, Suffix) -> iolist_to_binary([Prefix, integer_to_list(Slot), Suffix]).
%% Poll finite evidence with a bounded wall-clock horizon; no timeout changes device state.
-spec wait(fun(() -> wait | {ok, term()})) -> term().
wait(Fun) -> wait(Fun, erlang:monotonic_time(millisecond) + 10000).
%% Retrying a read cannot allocate a new incarnation or replay a source command.
-spec wait(fun(() -> wait | {ok, term()}), integer()) -> term().
wait(Fun, Deadline) ->
    case Fun() of {ok, Result} -> Result; wait ->
        true = erlang:monotonic_time(millisecond) < Deadline,
        receive after 1 -> ok end, wait(Fun, Deadline)
    end.
