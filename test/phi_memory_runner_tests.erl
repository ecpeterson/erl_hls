-module(phi_memory_runner_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(DISTANCE, 1).
-define(CUTOFF_STEP, 0).
-define(LINE_Y, 0).
-define(REQUEST_ID, 16#cafe).
-define(TIMEOUT, 1000).

runner_routes_and_closeout_test() ->
    {Fabric, Runner} = start_runner(?TIMEOUT),
    try
        ExpectedRoutes = maps:from_list([
            {Route, Runner}
            || {Route, _Stream} <- phi_memory_wire:event_routes(boundary())
        ]),
        ?assertEqual(
            ExpectedRoutes,
            phi_memory_fabric_fixture:route_owners(Fabric)
        ),

        [CutoffSend] = phi_memory_fabric_fixture:await_sends(
            Fabric,
            1,
            ?TIMEOUT
        ),
        ?assertEqual(encoded(cutoff_command()), CutoffSend),

        Correction = #phi_correction{
            step = ?CUTOFF_STEP,
            x = 0,
            y = 0,
            direction = ?PHI_NORTH_MASK
        },
        ok = deliver(Fabric, x_decoder_events, Correction),
        [_Cutoff, UpdateSend] = phi_memory_fabric_fixture:await_sends(
            Fabric,
            2,
            ?TIMEOUT
        ),
        {Coordinate, Pauli} = phi_noise_topology:correction_update(
            x,
            Correction,
            ?DISTANCE
        ),
        {DataX, DataY} = Coordinate,
        Update = {control_router, data,
            {DataX, DataY, DataX, DataY},
            #pauli_update{pauli = Pauli}},
        ?assertEqual(encoded(Update), UpdateSend),

        Quiet = ?PHENOM_QUIET_MASK,
        ok = deliver(Fabric, x_decoder_events, #phi_status{
            step = ?CUTOFF_STEP,
            x = 0,
            y = 0,
            flags = Quiet
        }),
        ok = deliver(Fabric, z_decoder_events, #phi_status{
            step = ?CUTOFF_STEP,
            x = 0,
            y = 0,
            flags = Quiet
        }),
        [_, _, QuerySend] =
            phi_memory_fabric_fixture:await_sends(
                Fabric,
                3,
                ?TIMEOUT
            ),
        ?assertEqual(encoded(query_command()), QuerySend),

        ok = deliver(Fabric, data_measurements, #pauli_reply{
            request_id = ?REQUEST_ID,
            x = 0,
            y = ?LINE_Y,
            anticommutes = 1
        }),
        ?assertEqual({ok, 1}, phi_memory_runner:await(Runner))
    after
        stop(Runner, Fabric)
    end.

unknown_decoder_selector_fails_test() ->
    {Fabric, Runner} = start_runner(?TIMEOUT),
    try
        Route = route(x_decoder_events),
        Header = {16#ff, 0, phi_memory_wire:version()},
        ok = phi_memory_fabric_fixture:deliver(
            Fabric,
            Route,
            Header,
            <<0:96>>
        ),
        ?assertEqual(
            {error, {wire, selector}},
            phi_memory_runner:await(Runner)
        )
    after
        stop(Runner, Fabric)
    end.

malformed_boundary_version_fails_test() ->
    {Fabric, Runner} = start_runner(?TIMEOUT),
    try
        Status = #phi_status{
            step = ?CUTOFF_STEP,
            x = 0,
            y = 0,
            flags = ?PHENOM_QUIET_MASK
        },
        Route = route(x_decoder_events),
        Header = {
            phi_halo_cell:pack_tag(phi_status),
            0,
            phi_memory_wire:version() + 1
        },
        ok = phi_memory_fabric_fixture:deliver(
            Fabric,
            Route,
            Header,
            phi_halo_cell:pack(Status)
        ),
        ?assertEqual(
            {error, {wire, frame}},
            phi_memory_runner:await(Runner)
        )
    after
        stop(Runner, Fabric)
    end.

timeout_fails_cleanly_test() ->
    {Fabric, Runner} = start_runner(20),
    try
        ?assertEqual({error, timeout}, phi_memory_runner:await(Runner))
    after
        stop(Runner, Fabric)
    end.

fabric_exit_aborts_experiment_test() ->
    {Fabric, Runner} = start_runner(?TIMEOUT),
    try
        ok = phi_memory_fabric_fixture:stop(Fabric),
        ?assertEqual(
            {error, {fabric_down, normal}},
            phi_memory_runner:await(Runner)
        )
    after
        stop(Runner, Fabric)
    end.

start_runner(Timeout) ->
    {ok, Fabric} = phi_memory_fabric_fixture:start_link(),
    {ok, Runner} = phi_memory_runner:start_link(Fabric, options(), Timeout),
    {Fabric, Runner}.

options() ->
    #{
        distance => ?DISTANCE,
        first_quiet_step => ?CUTOFF_STEP,
        line_y => ?LINE_Y,
        measurement => z,
        request_id => ?REQUEST_ID
    }.

cutoff_command() ->
    {control_router, noise, {0, 0, 0, 1}, #noise_cutoff{
        first_quiet_step = ?CUTOFF_STEP
    }}.

query_command() ->
    {control_router, data, {0, ?LINE_Y, 0, ?LINE_Y}, #pauli_query{
        request_id = ?REQUEST_ID,
        measurement = z
    }}.

encoded(Command) ->
    {ok, Route, Header, Payload} = phi_memory_wire:encode_command(
        Command,
        boundary()
    ),
    {Route, Header, Payload}.

deliver(Fabric, Stream, Record = #phi_correction{}) ->
    deliver(Fabric, Stream, phi_halo_cell, phi_correction, Record);
deliver(Fabric, Stream, Record = #phi_status{}) ->
    deliver(Fabric, Stream, phi_halo_cell, phi_status, Record);
deliver(Fabric, Stream, Record = #pauli_reply{}) ->
    deliver(Fabric, Stream, phenom_data_cell, pauli_reply, Record).

deliver(Fabric, Stream, Module, Schema, Record) ->
    Header = {Module:pack_tag(Schema), 0, phi_memory_wire:version()},
    phi_memory_fabric_fixture:deliver(
        Fabric,
        route(Stream),
        Header,
        Module:pack(Record)
    ).

route(Stream) ->
    {Route, Stream} = lists:keyfind(
        Stream,
        2,
        phi_memory_wire:event_routes(boundary())
    ),
    Route.

boundary() ->
    phi_memory_boundary:contract(?DISTANCE).

stop(Runner, Fabric) ->
    stop_if_alive(phi_memory_runner, Runner),
    stop_if_alive(phi_memory_fabric_fixture, Fabric).

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
