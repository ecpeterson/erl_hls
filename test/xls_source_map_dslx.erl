-module(xls_source_map_dslx).
-moduledoc "Writes ordinary actor bundles whose real XLS errors exercise actor, include and source-helper origins. Called by the source_maps regression before its Python converter driver; no external tools run here.".
%% Regression fixture preparation.
-export([write/1]).

%% Each expected line is chosen here, independently of emitted source-map ranges.
-type fixture() :: #{name := binary(), expression := iodata(),
    source := binary() | null, line := pos_integer() | null,
    extras := [{file:filename(), iodata()}]}.

-doc "Emits three deliberately ill-typed actor bundles and one valid control under a fresh staging directory. Retains original sources and explicit expected locations in cases.json; raises on lowering or file errors.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Cases = [
        #{name => <<"actor">>, expression => "Value + true",
            source => <<"actor.erl">>, line => 23, extras => []},
        #{name => <<"include">>, expression => "adjust(Value)",
            source => <<"include/callbacks.hrl">>, line => 37,
            extras => [{"include/callbacks.hrl", at_line([
                "-spec adjust(hls_nums:u32()) -> hls_nums:u32().",
                "adjust(Value) ->"
            ], 37, "  Value + true.")}]},
        #{name => <<"remote">>, expression => "remote_math:value(Value)",
            source => <<"remote_math.erl">>, line => 49,
            extras => [{"remote_math.erl", at_line([
                "-module(remote_math).", "-export([value/1]).",
                "-spec value(hls_nums:u32()) -> hls_nums:u32().", "value(Value) ->"
            ], 49, "  Value + true.")}]},
        #{name => <<"control">>, expression => "Value + 1",
            source => null, line => null, extras => []}
    ],
    lists:foreach(fun(Case) -> write_case(Stage, Case) end, Cases),
    Expectations = [maps:with([name, source, line], Case) || Case <- Cases],
    ok = file:write_file(filename:join(Stage, "cases.json"), json:encode(Expectations), [exclusive]),
    ok.

%% Compile from source-only files so includes and imported modules retain their own origins.
-spec write_case(file:filename(), fixture()) -> ok.
write_case(Stage, #{name := Name, expression := Expression, extras := Extras}) ->
    Directory = filename:join([Stage, "sources", binary_to_list(Name)]),
    Include = case Name of
        <<"include">> -> "-include(\"include/callbacks.hrl\").\n";
        _ -> []
    end,
    lists:foreach(fun({Relative, Body}) ->
        Path = filename:join(Directory, Relative),
        ok = filelib:ensure_dir(Path),
        ok = file:write_file(Path, Body, [exclusive])
    end, [{"actor.erl", [actor(Expression), Include]} | Extras]),
    _ = hls_compile:actor(filename:join(Directory, "actor.erl"), #{},
        filename:join([Stage, "emitted", binary_to_list(Name)])),
    ok.

%% Keep the callback error on a fixed source line while varying only its numerical expression.
-spec actor(iodata()) -> iodata().
actor(Expression) -> at_line([
    "-module(source_maps_actor).", "-behavior(hls_statem).",
    "-hls_data(cell).", "-hls_tags([request, report]).", "-hls_phases([waiting]).",
    "-hls_outputs([out]).", "-hls_mailbox_capacity(2).",
    "-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).",
    "-record(request, {value = hls_type:zero() :: hls_nums:u32()}).",
    "-record(report, {value = hls_type:zero() :: hls_nums:u32()}).",
    "init([]) -> {ok, waiting, #cell{}}.",
    "waiting(enter, _, Cell) -> {Cell, [{cast, out, #report{value = Cell#cell.value}}]};",
    "waiting(cast, #request{value = Value}, Cell) ->"
], 23, ["  {repeat_phase, Cell#cell{value = ", Expression, "}, consume}."]).

%% Insert blank source lines before the independently specified diagnostic location.
-spec at_line([iodata()], pos_integer(), iodata()) -> iodata().
at_line(Prefix, Line, Body) when length(Prefix) < Line ->
    [[Text, "\n"] || Text <- Prefix ++ lists:duplicate(Line - length(Prefix) - 1, []) ++ [Body]].
