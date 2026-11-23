-module(xls_protocol_spacetime_cli).
-moduledoc "Command boundary for the optional passive observer. Select the spacetime rebar profile first; these commands prepare or interpret files and never invoke external tools or the application stimulus.".

%% Entrypoint used by the repository's optional observer launcher.
-export([main/0]).

-doc "Dispatches prepare, capture and qualify with explicit input files and fresh output directories. Prints the completed manifest as JSON. Invalid arguments exit 2; input/interpretation failures exit 1 with the original reason and stack, leaving diagnostics and partial outputs intact.".
-spec main() -> no_return().
main() ->
    try
        Result = command(init:get_plain_arguments()),
        io:put_chars([json:encode(Result), $\n]),
        halt(0)
    catch
        error:usage ->
            io:put_chars(
                standard_error,
                "usage: hls-spacetime-observer prepare CONFIG FRESH_DIRECTORY\n"
                "       hls-spacetime-observer capture PREPARED TRACE FRESH_DIRECTORY\n"
                "       hls-spacetime-observer qualify CATALOGUE BUNDLE CANDIDATES WITNESS FRESH_DIRECTORY\n"
            ),
            halt(2);
        Class:Reason:Stack ->
            io:format(standard_error, "Observer failed: ~p:~p~n~p~n", [Class, Reason, Stack]),
            halt(1)
    end.

%% Preparation publishes passive inputs without executing the generated external build script.
-spec command([string()]) -> map().
command(["prepare", Config, Output]) ->
    xls_protocol_spacetime_workflow:write(xls_protocol_spacetime_workflow:prepare(Config), Output);
%% Conversion trusts only a hash-bound local preparation and records incomplete capture status.
command(["capture", Prepared, Trace, Output]) ->
    xls_protocol_spacetime_workflow:write_capture(Prepared, Trace, Output);
%% Physical claims require independent correspondence evidence; this command never discovers it.
command(["qualify", Catalogue, Bundle, Candidates, Witness, Output]) ->
    xls_protocol_spacetime_workflow:write_qualification(
        Catalogue, Bundle, Candidates, Witness, Output
    );
command(_) ->
    error(usage).
