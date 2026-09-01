%%%% phi_memory_demo
%%%%
%%%% Shared distance-three fixture for CPU and transported phi closeout.

-module(phi_memory_demo).
-moduledoc """
Defines and runs the deterministic distance-three phi memory demo.

`fixture/0` is the single authority for the noise rate, cutoff, logical line,
measurement, request ID, and regression result used by both the pure ERTS and
ERTS-plus-Icarus paths. `run_cpu/0` realizes the compact topology with
`phi_memory_cpu_fabric`; the transported path gives the same options to
`phi_memory_runner` around an `hls_fabric`.

The expected parity is a regression golden for this seeded plumbing fixture,
not a decoder threshold or logical-error-rate claim.
""".

-export([fixture/0, run_cpu/0, run_cpu/1]).

-type fixture() :: #{
    distance := 3,
    noise_rate := hls_nums:u32(),
    options := phi_memory_experiment:options(),
    expected := {ok, 0 | 1}
}.

-doc "Returns the shared deterministic distance-three fixture.".
-spec fixture() -> fixture().
fixture() ->
    #{
        distance => 3,
        noise_rate => 16#80000000,
        options => #{
            distance => 3,
            first_quiet_step => 16,
            line_y => 4,
            measurement => z,
            request_id => 16#504849
        },
        expected => {ok, 1}
    }.

-doc "Runs the pure ERTS fixture with a five-second closeout timeout.".
-spec run_cpu() -> {ok, 0 | 1} | {error, term()}.
run_cpu() ->
    run_cpu(5000).

-doc "Runs the pure ERTS fixture with an explicit timeout in milliseconds.".
-spec run_cpu(pos_integer()) -> {ok, 0 | 1} | {error, term()}.
run_cpu(Timeout) when Timeout > 0 ->
    #{
        distance := Distance,
        noise_rate := NoiseRate,
        options := Options
    } = fixture(),
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(Distance, NoiseRate),
    try
        {ok, Runner} = phi_memory_runner:start_link(
            Fabric,
            Options,
            Timeout
        ),
        try
            phi_memory_runner:await(Runner)
        after
            stop_if_alive(phi_memory_runner, Runner)
        end
    after
        stop_if_alive(phi_memory_cpu_fabric, Fabric)
    end.

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
