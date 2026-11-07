-module(hls_spacetime_cli).
-moduledoc """
Offline command boundary for the standalone spacetime library. Capture adapters own trace interpretation; Vivado owns extraction; this command validates and joins their saved artifacts. It never invokes either tool or discovers a compiler checkout.
""".
%% Escript callback and testable command dispatcher.
-export([main/1, run/1]).

-doc "Runs the offline command, prints a JSON summary, and exits nonzero with a concise diagnostic on failure. Use --help for the explicit input/output contract.".
-spec main([string()]) -> ok | no_return().
main(Arguments) ->
    try run(Arguments) of
        help -> io:put_chars(usage());
        Result -> io:put_chars([json:encode(Result), $\n])
    catch
        error:Reason ->
            io:format(standard_error, "spacetime: ~P~n", [Reason, 12]),
            halt(1)
    end.

-doc "Dispatches validate BUNDLE.etf; import EXPORT IDENTITY.term OUTPUT; or join BUNDLE.etf CATALOGUE.etf CLAIMS.etf OUTPUT. All inputs are trusted local files. Outputs require new directories. Import identity is one Erlang map containing build and checkpoint; join independently validates all references and supplied claims. Returns a summary or raises the underlying contract/file error.".
-spec run([string()]) -> help | hls_spacetime:summary() | hls_spacetime_physical:summary().
run(["--help"]) ->
    help;
run(["validate", Path]) ->
    hls_spacetime:validate(hls_spacetime_artifact:read(Path));
run(["import", Directory, Identity, Output]) ->
    {ok, [#{build := Build, checkpoint := Checkpoint}]} = file:consult(Identity),
    Catalogue = hls_spacetime_import:read(Directory, Build, Checkpoint),
    hls_spacetime_artifact:write_catalogue(Catalogue, Output);
run(["join", BundlePath, CataloguePath, ClaimsPath, Output]) ->
    Bundle = hls_spacetime_artifact:read(BundlePath),
    Catalogue = hls_spacetime_artifact:read(CataloguePath),
    Claims = hls_spacetime_artifact:read(ClaimsPath),
    Joined = hls_spacetime_import:attach(Bundle, Catalogue, Claims),
    hls_spacetime_artifact:write_bundle(Joined, Output);
run(_) ->
    error({usage, usage()}).

%% Positional file arguments avoid shell interpolation and implicit project discovery.
-spec usage() -> binary().
usage() ->
    <<
        "spacetime validate BUNDLE.etf\n"
        "spacetime import EXPORT_DIRECTORY IDENTITY.term FRESH_OUTPUT\n"
        "spacetime join BUNDLE.etf CATALOGUE.etf CLAIMS.etf FRESH_OUTPUT\n"
        "Trusted raw ETF only (256 MiB each); no compressed ETF. Import identity: #{build => #{source => <<...>>, rtl => <<...>>, observation => <<...>>}, checkpoint => <<SHA256>>}.\n"
        "Native extraction, producer claim qualification and simulation are separate commands; this command never infers physical correspondence.\n"
    >>.
