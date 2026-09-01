%%%% phi_memory_demo
%%%%
%%%% Shared distance-three fixture for CPU and transported phi closeout.

-module(phi_memory_demo).
-moduledoc """
Defines and runs the deterministic distance-three phi memory demo.

`fixture/0` is the single authority for the noise rate, cutoff, logical line,
measurement, request ID, and compact regression summary used by both the pure
ERTS and ERTS-plus-Icarus paths. `run_cpu/0` realizes the compact topology
with `phi_memory_cpu_fabric`; the transported path gives the same options to
`phi_memory_runner` around an `hls_fabric`.

The full witness contains every accepted correction and every final data-qubit
Pauli. The demo script carries the CPU-produced term to the Icarus host for a
direct comparison. The checked summary is deliberately small: it catches
shared drift and establishes that the fixture exercises nonidentity Paulis and
decoder corrections without committing a long schedule trace.
""".

-export([
    fixture/0,
    run_cpu/0,
    run_cpu/1,
    summary/1,
    verify/1,
    witness_envelope/1,
    decode_witness_envelope/1
]).

-type fixture() :: #{
    distance := 3,
    noise_rate := hls_nums:u32(),
    options := phi_memory_experiment:options(),
    expected_summary := map()
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
        expected_summary => #{
            closeout_step => 21,
            correction_count => 84,
            pauli_counts => #{i => 4, x => 4, y => 2, z => 8},
            row => #{y => 4, measurement => z, parity => 1}
        }
    }.

-doc "Runs the pure ERTS fixture with a five-second closeout timeout.".
-spec run_cpu() ->
    {ok, phi_memory_experiment:witness()} | {error, term()}.
run_cpu() ->
    run_cpu(5000).

-doc "Runs the pure ERTS fixture with an explicit timeout in milliseconds.".
-spec run_cpu(pos_integer()) ->
    {ok, phi_memory_experiment:witness()} | {error, term()}.
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

-doc "Returns the compact regression summary of one canonical witness.".
-spec summary(phi_memory_experiment:witness()) -> map().
summary(#{
    closeout_step := CloseoutStep,
    corrections := Corrections,
    data_paulis := DataPaulis,
    row := Row
}) ->
    Paulis = [Pauli || {_Coordinate, Pauli} <- DataPaulis],
    #{
        closeout_step => CloseoutStep,
        correction_count => length(Corrections),
        pauli_counts => maps:from_list([
            {Pauli, length([ok || Value <- Paulis, Value =:= Pauli])}
            || Pauli <- [i, x, y, z]
        ]),
        row => Row
    }.

-doc "Checks the full witness shape and the fixture's compact golden.".
-spec verify({ok, phi_memory_experiment:witness()} | {error, term()}) ->
    ok | {error, term()}.
verify({ok, Witness = #{corrections := [_ | _], data_paulis := DataPaulis}}) ->
    Nonidentity = [
        Pauli || {_Coordinate, Pauli} <- DataPaulis, Pauli =/= i
    ],
    #{expected_summary := Expected} = fixture(),
    case {Nonidentity, summary(Witness)} of
        {[_ | _], Expected} -> ok;
        {[], _Actual} -> {error, trivial_pauli_frame};
        {_, Actual} -> {error, {summary, Expected, Actual}}
    end;
verify({ok, _Witness}) ->
    {error, trivial_correction_trace};
verify({error, Reason}) ->
    {error, Reason}.

-doc "Wraps a verified CPU result with the fixture that produced it.".
-spec witness_envelope({ok, phi_memory_experiment:witness()}) -> map().
witness_envelope(Result) ->
    ok = verify(Result),
    #{
        version => 1,
        fixture => maps:remove(expected_summary, fixture()),
        result => Result
    }.

-doc "Checks and extracts one staged CPU witness envelope.".
-spec decode_witness_envelope(term()) ->
    {ok, phi_memory_experiment:options(),
        {ok, phi_memory_experiment:witness()}} |
    {error, term()}.
decode_witness_envelope(#{
    version := 1,
    fixture := CpuFixture = #{options := Options},
    result := Result = {ok, #{}}
}) ->
    LocalFixture = maps:remove(expected_summary, fixture()),
    case {CpuFixture, verify(Result)} of
        {LocalFixture, ok} -> {ok, Options, Result};
        {LocalFixture, Error} -> Error;
        _ -> {error, {fixture, LocalFixture, CpuFixture}}
    end;
decode_witness_envelope(_Envelope) ->
    {error, witness_envelope}.

stop_if_alive(Module, Pid) ->
    case is_process_alive(Pid) of
        true -> Module:stop(Pid);
        false -> ok
    end.
