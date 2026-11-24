-module(hls_dma_device).
-moduledoc """
Board bring-up and test drivers use these Linux endpoint checks before creating a broker. It manages device discovery and broker shutdown, not compiler artifacts or actor placement.

Owns Linux lifecycle checks for one HLS DMA mailbox endpoint.

Boot can load the mailbox driver before or after platform enumeration. `await/3`
therefore rescans the module and device manager, attempts an idempotent bind,
and treats the observed character device as authoritative. Status waits expose
the final sysfs record even when the requested quiescent policy is not reached,
so a caller can report the hardware boundary that failed.
""".

%% Linux endpoint discovery and health.
-export([await/3, endpoint_state/2, status/3, idle/1, healthy/1, status_line/2]).
%% Broker lifecycle checks.
-export([await_broker/2, close_broker/2]).
-export_type([status_policy/0]).

-define(DRIVER, "/sys/bus/platform/drivers/hls-dma-mailbox").

-doc "Selects strict idle status or application-idle status permitting one unread frame.".
-type status_policy() :: idle | application.

-doc "Recovers a missed probe and waits up to Timeout milliseconds for the endpoint path.".
-spec await(file:filename(), string(), non_neg_integer()) -> ok.
await(Path, Device, Timeout) when Timeout >= 0 ->
    _ = os:cmd("modprobe hls_dma_mailbox 2>&1"),
    ok = bind_if_unbound(Device),
    _ = os:cmd("mdev -s 2>&1"),
    await_present(Path, Device, deadline(Timeout)).

-doc "Reports module, platform, driver and misc-device enumeration state.".
-spec endpoint_state(file:filename(), string()) -> map().
endpoint_state(Path, Device) ->
    Platform = platform_path(Device),
    #{
        module_loaded => filelib:is_dir("/sys/module/hls_dma_mailbox"),
        platform_device => filelib:is_dir(Platform),
        driver_bound => filelib:is_dir(Platform ++ "/driver"),
        misc_device => filelib:is_dir("/sys/class/misc/" ++ filename:basename(Path))
    }.

-doc "Returns the first status matching Policy, or the final record after Timeout milliseconds.".
-spec status(string(), status_policy(), non_neg_integer()) -> binary().
status(Device, Policy, Timeout) when Timeout >= 0 ->
    Path = platform_path(Device) ++ "/status",
    await_status(Path, Policy, deadline(Timeout)).

-doc "Tests that a status record is fully idle with no latched failure.".
-spec idle(binary()) -> boolean().
idle(Status) ->
    has_fields(Status, [
        <<"tx_busy=0">>,
        <<"rx_full=0">>,
        <<"rx_active=0">>,
        <<"fault=0">>,
        <<"failed=0">>
    ]).

-doc "Tests that an application endpoint is idle apart from a complete unread frame.".
-spec healthy(binary()) -> boolean().
healthy(Status) ->
    has_fields(Status, [
        <<"tx_busy=0">>,
        <<"rx_active=0">>,
        <<"fault=0">>,
        <<"failed=0">>
    ]).

-doc "Prefixes a complete newline-terminated sysfs record with its logical endpoint.".
-spec status_line(atom(), binary()) -> iodata().
status_line(Endpoint, Status) ->
    [<<"dma role_endpoint=">>, atom_to_list(Endpoint), <<" ">>, Status].

-doc "Waits up to Timeout milliseconds for all broker writes and receipts to retire.".
-spec await_broker(pid(), non_neg_integer()) -> map().
await_broker(Broker, Timeout) when Timeout >= 0 ->
    await_broker_until(Broker, deadline(Timeout)).

-doc "Stops a broker and waits up to Timeout milliseconds for its endpoint lease to close.".
-spec close_broker(pid(), non_neg_integer()) -> ok | {error, timeout}.
close_broker(Broker, Timeout) when Timeout >= 0 ->
    #{io := #{lease := Lease}} = hls_fabric:info(Broker),
    ok = hls_fabric:stop(Broker),
    hls_fabric:await_closed(Lease, Timeout).

%% Bind a present platform device only when automatic probing missed it.
-spec bind_if_unbound(string()) -> ok.
bind_if_unbound(Device) ->
    Platform = platform_path(Device),
    case filelib:is_dir(Platform) andalso not filelib:is_dir(Platform ++ "/driver") of
        true ->
            %% A concurrent automatic probe may report busy. Enumeration below
            %% remains the authority for whether the bind completed.
            _ = file:write_file(?DRIVER ++ "/bind", Device),
            ok;
        false ->
            ok
    end.

%% Poll the stable character-device alias without opening it before the broker.
-spec await_present(file:filename(), string(), integer()) -> ok.
await_present(Path, Device, Deadline) ->
    case file:read_file_info(Path) of
        {ok, _} ->
            ok;
        {error, enoent} ->
            case before_deadline(Deadline) of
                true ->
                    timer:sleep(10),
                    await_present(Path, Device, Deadline);
                false ->
                    error({endpoint, Path, enoent, endpoint_state(Path, Device)})
            end;
        {error, Reason} ->
            error({endpoint, Path, Reason, endpoint_state(Path, Device)})
    end.

%% Poll one public status record until the requested quiescent policy holds.
-spec await_status(file:filename(), status_policy(), integer()) -> binary().
await_status(Path, Policy, Deadline) ->
    {ok, Status} = file:read_file(Path),
    case matches(Policy, Status) orelse not before_deadline(Deadline) of
        true ->
            Status;
        false ->
            timer:sleep(1),
            await_status(Path, Policy, Deadline)
    end.

%% Apply the caller-selected public status policy.
-spec matches(status_policy(), binary()) -> boolean().
matches(idle, Status) -> idle(Status);
matches(application, Status) -> healthy(Status).

%% Require every exact key/value token without depending on target-side parsers.
-spec has_fields(binary(), [binary()]) -> boolean().
has_fields(Status, Fields) ->
    lists:all(fun(Field) -> binary:match(Status, Field) =/= nomatch end, Fields).

%% Wait for the broker's public queues and outstanding receipt to become empty.
-spec await_broker_until(pid(), integer()) -> map().
await_broker_until(Broker, Deadline) ->
    Info =
        #{
            tx := #{queued := Queued, active := Active},
            rx := #{outstanding := Outstanding, buffered := Buffered}
        } = hls_fabric:info(Broker),
    case {Queued, Active, Outstanding, Buffered} of
        {0, none, 0, none} ->
            Info;
        _ ->
            case before_deadline(Deadline) of
                true ->
                    timer:sleep(1),
                    await_broker_until(Broker, Deadline);
                false ->
                    error({broker_drain_timeout, Info})
            end
    end.

%% Resolve one platform device under the kernel's stable sysfs namespace.
-spec platform_path(string()) -> file:filename().
platform_path(Device) -> "/sys/bus/platform/devices/" ++ Device.

%% Convert a duration to one monotonic deadline shared by the whole operation.
-spec deadline(non_neg_integer()) -> integer().
deadline(Timeout) -> erlang:monotonic_time(millisecond) + Timeout.

%% Compare a monotonic deadline without assuming an epoch.
-spec before_deadline(integer()) -> boolean().
before_deadline(Deadline) -> erlang:monotonic_time(millisecond) < Deadline.
