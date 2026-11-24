-module(hls_spacetime_cli).
-moduledoc """
Offline command boundary for the standalone spacetime library. Capture adapters own trace interpretation; Vivado owns extraction; this command validates and joins their saved artifacts. It never invokes either tool or discovers a compiler checkout.
""".
%% Escript callback and testable command dispatcher.
-export([main/1, run/1]).

-define(MAX_JSON_BYTES, 256 * 1024 * 1024).

%% One fresh SDF arc sidecar is content-bound without changing the source timing evidence.
-type sdf_summary() :: #{
    file := binary(),
    bytes := non_neg_integer(),
    sha256 := binary(),
    arcs := non_neg_integer(),
    issues := non_neg_integer(),
    source := hls_target_sdf:source()
}.

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

-doc "Dispatches validate BUNDLE.etf; import EXPORT IDENTITY.term OUTPUT; join BUNDLE.etf CATALOGUE.etf CLAIMS.etf OUTPUT; or sdf-arcs INPUT SHA256 fast|slow FRESH_JSON. All inputs are trusted local files. Import/join outputs require new directories; sdf-arcs writes one exclusive file, at most 256 MiB including its trailing newline. Import identity is one Erlang map containing build and checkpoint; join independently validates all references and supplied claims. Returns a summary or raises the underlying contract/file error.".
-spec run([string()]) ->
    help | hls_spacetime:summary() | hls_target_physical:summary() | sdf_summary().
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
run(["sdf-arcs", Input, Digest, CornerName, Output]) ->
    sdf_arcs(Input, Digest, corner(CornerName), Output);
run(_) ->
    error({usage, usage()}).

%% Fixed vocabulary prevents input strings from creating atoms in the command process.
-spec corner(string()) -> fast | slow.
corner("fast") -> fast;
corner("slow") -> slow;
corner(Value) -> error({spacetime_cli, {sdf_corner, Value}}).

%% The complete encoded output is bounded before exclusive creation; failures never overwrite evidence.
-spec sdf_arcs(file:filename(), string(), fast | slow, file:filename()) -> sdf_summary().
sdf_arcs(Input, Digest, Corner, Output) ->
    Parsed = hls_target_sdf:read(Input, #{
        sha256 => list_to_binary(Digest), corner => Corner, mode => sta
    }),
    Projection = hls_target_sdf_arcs:project(Parsed),
    Data = [json:encode(Projection), $\n],
    Size = iolist_size(Data),
    case Size =< ?MAX_JSON_BYTES of
        true -> ok;
        false -> error({spacetime_cli, {sdf_json_limit, Size, ?MAX_JSON_BYTES}})
    end,
    Sha256 = binary:encode_hex(crypto:hash(sha256, Data), lowercase),
    case file:write_file(Output, Data, [exclusive]) of
        ok -> ok;
        {error, Reason} -> error({spacetime_cli, {write, Output, Reason}})
    end,
    #{
        file => unicode:characters_to_binary(Output),
        bytes => Size,
        sha256 => Sha256,
        arcs => length(maps:get(arcs, Projection)),
        issues => length(maps:get(issues, Projection)),
        source => maps:get(source, Projection)
    }.

%% Positional file arguments avoid shell interpolation and implicit project discovery.
-spec usage() -> binary().
usage() ->
    <<
        "spacetime validate BUNDLE.etf\n"
        "spacetime import EXPORT_DIRECTORY IDENTITY.term FRESH_OUTPUT\n"
        "spacetime join BUNDLE.etf CATALOGUE.etf CLAIMS.etf FRESH_OUTPUT\n"
        "spacetime sdf-arcs INPUT.sdf SHA256 fast|slow FRESH_JSON\n"
        "SDF input/output are bounded at 256 MiB; SHA256 binds the exact raw input. The output file must not exist.\n"
        "Bundle/catalogue/claim inputs use trusted raw ETF (256 MiB each), not compressed ETF. Import identity: #{build => #{source => <<...>>, rtl => <<...>>, observation => <<...>>}, checkpoint => <<SHA256>>}.\n"
        "Native extraction, producer claim qualification and simulation are separate commands; this command never infers physical correspondence.\n"
    >>.
