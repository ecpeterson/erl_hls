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

-export([capture/2, from_forms/2, options/2, read/2, parse_file/1, parse_file/2,
    find_attribute/2, find_optional_attribute/2, find_function/3, find_spec/3]).
-export_type([context/0, option/0, compiler_option/0, form/0,
              record_declaration/0, record_field/0, function_spec/0]).

-doc "A compiler option; only preprocessing options are retained in source contexts.".
-type compiler_option() :: atom() | {atom(), term()} | {atom(), term(), term()}.
-doc "A preprocessed source form, including end-of-file and warning markers.".
-type form() :: erl_parse:abstract_form() | {eof, erl_anno:location()} |
                {warning, erl_parse:error_info()}.
-doc "An Erlang record declaration with typed or untyped fields.".
-type record_declaration() :: {attribute, erl_anno:anno(), record,
                              {atom(), [erl_parse:af_field_decl()]}}.
-doc "A record field declaration before any enclosing type annotation.".
-type record_field() :: {record_field, erl_anno:anno(), {atom, erl_anno:anno(), atom()}} |
    {record_field, erl_anno:anno(), {atom, erl_anno:anno(), atom()}, erl_parse:abstract_expr()}.
-doc "An abstract local or module-qualified function specification or callback declaration.".
-type function_spec() :: {attribute, erl_anno:anno(), spec | callback,
    {{atom(), arity()} | {module(), atom(), arity()}, [erl_parse:abstract_type()]}}.


-doc "An include path, macro definition or feature toggle accepted by options/2.".
-type option() :: {i, file:filename()} | {d, atom()} | {d, atom(), term()} |
    {feature, atom(), enable | disable}.
-doc "Build directory, source spelling and preprocessing inputs, optionally with expected include origins.".
-type context() :: #{
    directory := file:filename(),
    source_name := file:filename(),
    includes := [file:filename()],
    macros := [atom() | {atom(), term()}],
    features := [{feature, atom(), enable | disable}],
    origins => [file:filename()]
}.

-doc "Creates a preprocessing context anchored to the current directory; rejects unsupported options.".
-spec options(file:filename(), [option()]) -> context().
options(Filename, Options) when is_list(Options) ->
    lists:foreach(fun validate_option/1, Options),
    context(Filename, Options);
options(_Filename, Options) ->
    error({invalid_source_options, Options}).

-doc "Returns the source-context attribute for a parse transform, or no attribute for deterministic compilation.".
-spec capture([hls_source:form()], [hls_source:compiler_option()]) -> [tuple()].
capture(Forms = [{attribute, Line, file, {_SourceName, _}} | _], Options) ->
    ModuleOptions = lists:flatmap(fun
        ({attribute, _, compile, Values}) when is_list(Values) -> Values;
        ({attribute, _, compile, Value}) -> [Value];
        (_) -> []
    end, Forms),
    case lists:member(deterministic, Options ++ ModuleOptions) of
        true -> [];
        false -> [{attribute, Line, hls_source_context, from_forms(Forms, Options)}]
    end.

%% Available during analysis even when a deterministic build omits the
%% corresponding BEAM metadata. Only preprocessing options enter the context.
-doc "Recovers source context and include origins, including during deterministic compilation.".
-spec from_forms([hls_source:form()], [hls_source:compiler_option()]) -> context().
from_forms(Forms = [{attribute, _, file, {SourceName, _}} | _], Options) ->
    Context = case [C || {attribute, _, hls_source_context, C} <- Forms] of
        [Captured] -> Captured;
        [] -> context(SourceName, Options)
    end,
    Context#{origins => origins(Forms)}.

%% Capture only options that affect preprocessing.
-spec context(file:filename(), [compiler_option()]) -> context().
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

%% Validate user-supplied preprocessing options before constructing a context.
-spec validate_option(term()) -> ok.
validate_option({i, Path}) when is_list(Path), Path =/= [] -> ok;
validate_option({d, Name}) when is_atom(Name) -> ok;
validate_option({d, Name, _Value}) when is_atom(Name) -> ok;
validate_option({feature, Name, Mode}) when is_atom(Name),
        (Mode =:= enable orelse Mode =:= disable) -> ok;
validate_option(Option) -> error({invalid_source_option, Option}).

-doc "Preprocesses source in its captured build context and checks include origins. Uses at most one temporary peer when directories differ; raises on source errors.".
-spec read(file:filename(), context()) -> [hls_source:form()].
read(Filename, #{directory := Directory, source_name := SourceName,
        includes := Includes, macros := Macros, features := FeatureOptions} = Context) ->
    %% Select the original source spelling before entering a peer: get_cwd/0
    %% resolves directory symlinks, but ?FILE and include origins must not change.
    File = case filename:absname(Filename, Directory) =:=
            filename:absname(SourceName, Directory) of
        true -> SourceName;
        false -> Filename
    end,
    Forms = case file:get_cwd() of
        {ok, Directory} -> read_here(File, SourceName, Includes, Macros, FeatureOptions);
        {ok, _Elsewhere} -> read_in_directory(File, Context)
    end,
    ActualOrigins = origins(Forms),
    case maps:find(origins, Context) of
        error -> ok;
        {ok, ActualOrigins} -> ok;
        {ok, ExpectedOrigins} -> error({source_origins, ExpectedOrigins, ActualOrigins})
    end,
    %% Keep source-only consumers on the same preprocessing context as the
    %% parse transform. A peer read may already have attached this attribute.
    lists:flatmap(fun
        ({attribute, _, hls_source_context, _}) -> [];
        ({eof, Line} = Eof) -> [{attribute, erl_anno:new(Line), hls_source_context, Context}, Eof];
        (Form) -> [Form]
    end, Forms).

%% Collect unique source/include names as observed by the preprocessor.
-spec origins([form()]) -> [file:filename()].
origins(Forms) ->
    lists:usort([File || {attribute, _, file, {File, _}} <- Forms]).

%% Read in an isolated working directory without changing the caller's file server.
-spec read_in_directory(file:filename(), context()) -> [form()].
read_in_directory(Filename, Context = #{directory := Directory}) ->
    %% Relative include spellings affect ?FILE, including preprocessor
    %% conditions. Re-rooting the caller's file server would race other
    %% compilations; use peer's stdio connection without distribution/epmd.
    Paths = [filename:absname(Path) || Path <- code:get_path()],
    {ok, Peer, _Node} = peer:start_link(#{connection => standard_io,
        args => ["+S", "1:1", "+A", "1", "-pa" | Paths]}),
    try
        ok = peer:call(Peer, file, set_cwd, [Directory]),
        %% Re-enter read/2 using the peer's actual directory, so a relocated
        %% build reached through a symlink cannot recursively create peers.
        {ok, ActualDirectory} = peer:call(Peer, file, get_cwd, []),
        peer:call(Peer, ?MODULE, read,
            [Filename, Context#{directory := ActualDirectory}], 60000)
    after
        peer:stop(Peer)
    end.

%% OTP 28.0.2 epp:open/1 omits features/reserved_word_fun from its spec,
%% contradicting parse_file/2's documented options and actual implementation.
%% That infers no return here. Source-context tests cover feature preprocessing;
%% upstream master fixes it in erlang/otp@a19d9e0 (not yet in maint-28).
%% Remove this exemption after qualifying a toolchain with that correction.
-dialyzer({nowarn_function, read_here/5}).
%% Preprocess in the already selected build directory and report source errors.
-spec read_here(file:filename(), file:filename(), [file:filename()],
    [atom() | {atom(), term()}], [{feature, atom(), enable | disable}]) -> [form()].
read_here(File, SourceName, Includes, Macros, FeatureOptions) ->
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
                Errors -> hls_diagnostic:raise(source, source_errors, <<"Source preprocessing or parsing failed">>,
                    #{source => unicode:characters_to_binary(File), errors => lists:reverse(Errors)})
            end;
        {error, Reason} -> hls_diagnostic:raise(source, source_open, <<"Cannot open source file">>,
            #{source => unicode:characters_to_binary(File), reason => Reason, detail => unicode:characters_to_binary(file:format_error(Reason))})
    end.

%% Each epp/parser error retains the active include, location, formatter and original reason.
-type source_error() :: #{source := binary(), location := erl_anno:location(),
    module := module(), reason := term(), message := binary()}.

%% Parsing does not run transforms; formatter failures remain unexpected exceptions.
-spec source_errors([form() | {error, erl_parse:error_info()}], file:filename(), [source_error()]) -> [source_error()].
source_errors([{attribute, _, file, {File, _}} | Forms], _File, Errors) ->
    source_errors(Forms, File, Errors);
source_errors([{error, {Location, Module, Reason}} | Forms], File, Errors) ->
    source_errors(Forms, File, [#{source => unicode:characters_to_binary(File), location => Location, module => Module,
        reason => Reason, message => unicode:characters_to_binary(Module:format_error(Reason))} | Errors]);
source_errors([_ | Forms], File, Errors) -> source_errors(Forms, File, Errors);
source_errors([], _File, Errors) -> Errors.


-doc "Reads actor source with the compiler include directory and no caller preprocessing options.".
-spec parse_file(file:filename()) -> {ok, [form()]}.
parse_file(Filename) ->
    parse_file(Filename, []).

-doc "Reads source using caller options plus the compiler include directory, or an exact captured context. Captured contexts receive no additional include paths; source failures raise.".
-spec parse_file(file:filename(), [option()] | context()) -> {ok, [form()]}.
parse_file(Filename, Context) when is_map(Context) ->
    {ok, read(Filename, Context)};
parse_file(Filename, Options) ->
    Context = options(Filename, Options),
    #{includes := Includes} = Context,
    {ok, read(Filename, Context#{includes := Includes ++ application_includes()})}.

%% A source-only checkout can read its own headers before the application is loaded.
-spec application_includes() -> [file:filename()].
application_includes() ->
    case code:lib_dir(erl_hls) of
        {error, bad_name} -> [filename:absname("include")];
        Application -> [filename:join(Application, "include")]
    end.

-doc "Returns the first named attribute's value; raises when it is absent.".
-spec find_attribute([form()], atom()) -> term().
find_attribute(Forms, Atom) ->
    {value, {attribute, _Line, _Name, Value}} = lists:search(
        fun ({attribute, _, Name, _}) -> Name == Atom;
            (_) -> false
        end, Forms),
    Value.

-doc "Returns the first named attribute's value, or none when it is absent.".
-spec find_optional_attribute([form()], atom()) -> none | {ok, term()}.
find_optional_attribute(Forms, Atom) ->
    case lists:search(
        fun ({attribute, _, Name, _}) -> Name =:= Atom;
            (_) -> false
        end, Forms) of
        {value, {attribute, _, Atom, Value}} -> {ok, Value};
        false -> none
    end.

-doc "Returns the named function's source-ordered clauses; raises when it is absent.".
-spec find_function([form()], atom(), arity()) -> [erl_parse:abstract_clause(), ...].
find_function(Forms, Function, Arity) ->
    {value, {function, _, Function, Arity, Clauses}} = lists:search(
        fun ({function, _, Name, Count, _}) -> Function == Name andalso Arity == Count;
            (_) -> false
        end, Forms),
    Clauses.

-doc "Returns the first local specification for a function and arity; raises when it is absent.".
-spec find_spec([form()], atom(), arity()) -> function_spec().
find_spec(Forms, Function, Arity) ->
    {value, Spec} = lists:search(
        fun ({attribute, _, spec, {{Name, Count}, _}}) ->
                Function == Name andalso Arity == Count;
            (_) -> false
        end, Forms),
    Spec.
