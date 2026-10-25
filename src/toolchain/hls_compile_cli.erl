-module(hls_compile_cli).
-moduledoc "Standalone compiler frontend; independent of rebar and any fabric deployment.".
-export([main/0, run/1]).

-doc "Runs hlsc using the packaged compiler; --diagnostics selects text or JSON failures.".
-spec main() -> no_return().
main() -> hls_cli:main("hlsc", fun run/1).

-doc "Lowers an actor with explicit preprocessing and external schedule options. Include/import paths accumulate; later -D definitions replace earlier definitions of the same macro. --source-options reads a trusted Erlang list of hls_source options, including feature toggles; explicit CLI macros override these defaults. Values and paths are separate arguments, relative to the caller. Does not invoke XLS or rebar.".
-spec run([string()]) -> ok.
run([]) -> usage();
run(["--help"]) -> usage();
run(["emit", Source | Args]) ->
    Options = hls_cli:options(Args, [{"--output", output, value}, {"-I", includes, repeat},
        {"-D", defines, repeat}, {"--source-options", source_options, value},
        {"--dslx-path", imports, repeat}, {"--direct-actor-debug", debug, flag},
        {"--pipeline-stages", stages, value}]),
    Output = hls_cli:required(output, Options),
    SourceOptions = case maps:find(source_options, Options) of
        error -> [];
        {ok, Path} -> {ok, [Terms]} = file:consult(Path), Terms
    end,
    _ = hls_compile:actor(Source, #{source_options => last_defines(SourceOptions ++
        [{i, P} || P <- maps:get(includes, Options, [])] ++
        [define(D) || D <- maps:get(defines, Options, [])]),
        direct_actor_debug => maps:get(debug, Options, false),
        dslx_path => maps:get(imports, Options, []),
        pipeline_stages => hls_cli:integer(stages, maps:get(stages, Options, "2"))}, Output),
    ok;
run(Args) -> hls_diagnostic:raise(arguments, unknown_command,
    <<"Unknown compiler command">>, #{arguments => [unicode:characters_to_binary(Arg) || Arg <- Args]}).

%% OTP rejects duplicate predefined macros; remove overridden CLI/default definitions before preprocessing.
-spec last_defines([hls_source:option()]) -> [hls_source:option()].
last_defines(Options) ->
    {Effective, _} = lists:foldr(fun
        (Option = {d, Name}, Acc) -> keep_define(Name, Option, Acc);
        (Option = {d, Name, _}, Acc) -> keep_define(Name, Option, Acc);
        (Option, {Acc, Seen}) -> {[Option | Acc], Seen}
    end, {[], #{}}, Options),
    Effective.

%% Right-to-left traversal retains only the final definition without reordering other source options.
-spec keep_define(atom(), hls_source:option(), {[hls_source:option()], #{atom() => true}}) ->
    {[hls_source:option()], #{atom() => true}}.
keep_define(Name, Option, {Acc, Seen}) ->
    case is_map_key(Name, Seen) of
        true -> {Acc, Seen};
        false -> {[Option | Acc], Seen#{Name => true}}
    end.

%% Macro names and literal Erlang values are trusted compiler input, like source itself.
-spec define(string()) -> hls_source:option().
define(Value) ->
    case string:split(Value, "=") of
        [Name] when Name =/= [] -> {d, list_to_atom(Name)};
        [Name, Text] when Name =/= [] ->
            case erl_scan:string(Text ++ ".") of
                {ok, Tokens, _} ->
                    case erl_parse:parse_term(Tokens) of
                        {ok, Term} -> {d, list_to_atom(Name), Term};
                        _ -> hls_diagnostic:raise(arguments, invalid_define, <<"Macro definition must be NAME or NAME=TERM">>, #{option => <<"-D">>, value => unicode:characters_to_binary(Value)})
                    end;
                _ -> hls_diagnostic:raise(arguments, invalid_define, <<"Macro definition must be NAME or NAME=TERM">>, #{option => <<"-D">>, value => unicode:characters_to_binary(Value)})
            end;
        _ -> hls_diagnostic:raise(arguments, invalid_define, <<"Macro definition must be NAME or NAME=TERM">>, #{option => <<"-D">>, value => unicode:characters_to_binary(Value)})
    end.

%% Help describes the source/external-tool boundary rather than application presets.
-spec usage() -> ok.
usage() ->
    io:put_chars("Usage: hlsc emit SOURCE --output FRESH_DIRECTORY [-I DIRECTORY] [-D NAME[=TERM]]\n"
        "                 [--source-options FILE] [--dslx-path DIRECTORY]\n"
        "                 [--direct-actor-debug] [--pipeline-stages N] [--diagnostics text|json]\n"
        "Emits DSLX and source-build.json. XLS invocation and hardware qualification are separate.\n").
