-module(hls_source).
-moduledoc """
Preprocesses actor source with an explicit Erlang build context.

`options/2` accepts compiler-style include, macro, and feature options. Paths
are anchored when the context is created, so a later query need not run in the
build directory. `capture/2` records the preprocessing portion of the options
received by a parse transform; unrelated BEAM compiler options are ignored.

Contexts are build-local metadata, not artifact fingerprints. Includes and
`include_lib` dependencies are resolved again on every read. Deterministic
BEAM builds omit this metadata, as they omit the compiler's source path.
""".

-export([capture/2, options/2, read/2]).
-export_type([context/0, option/0]).

-type option() :: {i, file:filename()} | {d, atom()} | {d, atom(), term()} |
    {feature, atom(), enable | disable}.
-type context() :: #{
    directory := file:filename(),
    source_name := file:filename(),
    includes := [file:filename()],
    macros := [atom() | {atom(), term()}],
    features := [{feature, atom(), enable | disable}],
    origins => [file:filename()]
}.

-spec options(file:filename(), [option()]) -> context().
options(Filename, Options) when is_list(Options) ->
    lists:foreach(fun validate_option/1, Options),
    context(Filename, Options);
options(_Filename, Options) ->
    error({invalid_source_options, Options}).

-spec capture([erl_parse:abstract_form()], [compile:option()]) -> [tuple()].
capture(Forms = [{attribute, Line, file, {SourceName, _}} | _], Options) ->
    ModuleOptions = lists:flatmap(fun
        ({attribute, _, compile, Values}) when is_list(Values) -> Values;
        ({attribute, _, compile, Value}) -> [Value];
        (_) -> []
    end, Forms),
    case lists:member(deterministic, Options ++ ModuleOptions) of
        true -> [];
        false -> [{attribute, Line, hls_source_context,
            (context(SourceName, Options))#{origins => origins(Forms)}}]
    end.

context(SourceName, Options) ->
    {ok, Directory} = file:get_cwd(),
    #{
        directory => Directory,
        source_name => SourceName,
        includes => [Path || {i, Path} <- Options, is_list(Path)],
        macros => lists:flatmap(fun
            ({d, Name}) -> [Name];
            ({d, Name, Value}) -> [{Name, Value}];
            (_) -> []
        end, Options),
        features => [Option || Option = {feature, _, _} <- Options]
    }.

validate_option({i, Path}) when is_list(Path), Path =/= [] -> ok;
validate_option({d, Name}) when is_atom(Name) -> ok;
validate_option({d, Name, _Value}) when is_atom(Name) -> ok;
validate_option({feature, Name, Mode}) when is_atom(Name),
        (Mode =:= enable orelse Mode =:= disable) -> ok;
validate_option(Option) -> error({invalid_source_option, Option}).

-spec read(file:filename(), context()) -> [erl_parse:abstract_form()].
read(Filename, #{directory := Directory, source_name := SourceName,
        includes := Includes, macros := Macros, features := FeatureOptions} = Context) ->
    Forms = case file:get_cwd() of
        {ok, Directory} -> read_here(Filename, SourceName, Includes, Macros, FeatureOptions);
        {ok, _Elsewhere} -> read_in_directory(Filename, Context)
    end,
    ActualOrigins = origins(Forms),
    case maps:find(origins, Context) of
        error -> Forms;
        {ok, ActualOrigins} -> Forms;
        {ok, ExpectedOrigins} -> error({source_origins, ExpectedOrigins, ActualOrigins})
    end.

origins(Forms) ->
    lists:usort([File || {attribute, _, file, {File, _}} <- Forms]).

read_in_directory(Filename, Context = #{directory := Directory}) ->
    %% Relative include spellings affect ?FILE, including preprocessor
    %% conditions. Re-rooting the caller's file server would race other
    %% compilations; use peer's stdio connection without distribution/epmd.
    Paths = [filename:absname(Path) || Path <- code:get_path()],
    {ok, Peer, _Node} = peer:start_link(#{connection => standard_io,
        args => ["+S", "1:1", "+A", "1", "-pa" | Paths]}),
    try
        ok = peer:call(Peer, file, set_cwd, [Directory]),
        peer:call(Peer, ?MODULE, read, [Filename, Context], 60000)
    after
        peer:stop(Peer)
    end.

read_here(Filename, SourceName, Includes, Macros, FeatureOptions) ->
    %% module_info reports an absolute source path; recover the original
    %% spelling when it identifies this same file. Keep an explicitly
    %% supplied different path (for example, a compiler source-name override).
    File = case filename:absname(Filename) =:= filename:absname(SourceName) of
        true -> SourceName;
        false -> Filename
    end,
    {Features, ReservedWord} = case erl_features:keyword_fun(
            FeatureOptions, fun erl_scan:f_reserved_word/1) of
        {ok, Enabled} -> Enabled;
        {error, FeatureError} -> error({source_features, FeatureError})
    end,
    %% epp searches the including file's directory first. Keep the original
    %% working directory and main source directory behind it, as compile does.
    case epp:parse_file(File, [
        {source_name, SourceName},
        {includes, [".", filename:dirname(File) | Includes]},
        {macros, Macros},
        {features, Features},
        {reserved_word_fun, ReservedWord}
    ]) of
        {ok, Forms} ->
            case source_errors(Forms, SourceName, []) of
                [] -> Forms;
                Errors -> error({source_errors, lists:reverse(Errors)})
            end;
        {error, Reason} -> error({source_open, File, Reason})
    end.

source_errors([{attribute, _, file, {File, _}} | Forms], _File, Errors) ->
    source_errors(Forms, File, Errors);
source_errors([{error, {Location, Module, Reason}} | Forms], File, Errors) ->
    source_errors(Forms, File, [{File, Location, Module, Reason} | Errors]);
source_errors([_ | Forms], File, Errors) -> source_errors(Forms, File, Errors);
source_errors([], _File, Errors) -> Errors.
