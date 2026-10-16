-module(xls_phase_values_dslx).
-moduledoc "Emits phase-specialization witnesses without changing the source callback module.".
-export([write/1]).

-doc "Writes ordinary/specialized fixture modules with equal legal-state observations, malformed command witnesses and an invariant precondition for external proof tools.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {A, B, _, _} = xls_phase_specialize:from_file("test/xls_phase_values_fixture.erl", []),
    {ok, Probe} = file:read_file("test_data/xls_phase_values_probe.inc.x"),
    ok = filelib:ensure_dir(filename:join(Stage, "marker")),
    lists:foreach(fun({Name, Spec}) ->
        ok = file:write_file(filename:join(Stage, Name ++ ".x"), [xls_statem_codegen:emit(Spec), Probe])
    end, [{"phase_baseline", A}, {"phase_candidate", B}]),
    ok.
