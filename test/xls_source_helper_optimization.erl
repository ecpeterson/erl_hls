-module(xls_source_helper_optimization).
-moduledoc "Writes a source-derived helper module and constant/dynamic callers for a focused XLS optimization regression.".
%% External-tool fixture generation; expected values remain BEAM-owned.
-export([write/1]).

-doc "Writes one generated source bundle, two scalar probes and finite BEAM assertions into an existing directory. Does not run XLS.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Artifact = xls_parse:to_artifact("test/xls_remote_selection_fixture.erl"),
    Dependencies = xls_emitted:dependencies(Artifact),
    [Selector] = [Bytes || {Path, Bytes} <- maps:to_list(Dependencies),
        filename:basename(Path) =:= "xls_remote_selector.x"],
    true = binary:match(Selector, <<"pub fn choose(">>) =/= nomatch,
    Bytes = [xls_emitted:bytes(Artifact), probes(), assertions()],
    xls_emitted:write(xls_emitted:with_bytes(Artifact, Bytes),
        filename:join(Stage, "source_helpers.x")).

%% Use the generated public module interface directly: no handwritten selector implementation.
-spec probes() -> iodata().
probes() -> [
    "\n// The source helper's constant selector should disappear during XLS optimization.\n",
    "pub fn constant_probe(x: u32, y: u32) -> u32 {\n",
    "  let (value, _failure) = xls_remote_selector::choose(true, x, y);\n",
    "  value\n}\n",
    "// The same helper must retain selection when its Boolean input is dynamic.\n",
    "pub fn dynamic_probe(keep_left: bool, x: u32, y: u32) -> u32 {\n",
    "  let (value, _failure) = xls_remote_selector::choose(keep_left, x, y);\n",
    "  value\n}\n"
].

%% Distinct data values make the dynamic control observable in both directions.
-spec assertions() -> iodata().
assertions() -> [
    "#[test]\nfn source_helper_probes_match_beam() {\n",
    [io_lib:format(
        "  assert_eq(dynamic_probe(~s, u32:~p, u32:~p), u32:~p);\n",
        [atom_to_list(KeepLeft), X, Y, xls_remote_selector:choose(KeepLeft, X, Y)])
        || KeepLeft <- [false, true], X <- values(), Y <- values()],
    [io_lib:format("  assert_eq(constant_probe(u32:~p, u32:~p), u32:~p);\n",
        [X, Y, xls_remote_selector:choose(true, X, Y)]) || X <- values(), Y <- values()],
    "}\n"
].

%% Exercise low, sign-boundary and full-width values without an exhaustive word-sized domain.
-spec values() -> [non_neg_integer()].
values() -> [0, 1, 16#80000000, 16#ffffffff].
