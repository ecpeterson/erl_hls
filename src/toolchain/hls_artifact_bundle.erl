-module(hls_artifact_bundle).
-moduledoc "Packages generated source for independent external compilers. Clients own emission and scheduling policy.".
-export([open/1, snapshot/2, finish/3]).
-export_type([unit/0, library/0]).

-doc "One external compilation unit. All paths are relative to the bundle; codegen_flags are literal XLS arguments supplied by the emitter, never shell text. Each unit needs its own directory for intermediates.".
-type unit() :: #{role := binary(), directory := binary(), source := binary(),
    top := binary(), module := binary(), output := binary(), dslx_path := [binary()],
    codegen_flags := [binary()], rtl := [binary()]}.
-doc "A source tree, its relative bundle destination and the file extensions to copy recursively.".
-type library() :: {file:filename(), string(), [string()]}.

-doc "Creates a fresh output directory and returns its absolute path. Existing paths are rejected, including symlinks; partial output is retained on later failures.".
-spec open(file:filename()) -> string().
open(Output) ->
    Directory = filename:absname(Output),
    ok = filelib:ensure_dir(Directory),
    case file:make_dir(Directory) of
        ok -> Directory;
        {error, eexist} -> error({source_output_exists, Directory});
        {error, Reason} -> error({source_output, Directory, Reason})
    end.

-doc "Copies selected library files without overwriting, preserving source directories even when empty or containing only excluded file types. Destinations must stay within the bundle; missing source directories fail. Trusted source-tree symlinks are followed.".
-spec snapshot(file:filename(), [library()]) -> ok.
snapshot(Output, Libraries) ->
    lists:foreach(fun({Source, Relative, Extensions}) ->
        snapshot_tree(Source, filename:join(Output, relative(Relative)), Extensions)
    end, Libraries).

%% Import directories are part of the source tree even when no selected file lies below them.
-spec snapshot_tree(file:filename(), file:filename(), [string()]) -> ok.
snapshot_tree(Source, Target, Extensions) ->
    {ok, Names} = file:list_dir(Source),
    ok = filelib:ensure_dir(filename:join(Target, "placeholder")),
    lists:foreach(fun(Name) ->
        Input = filename:join(Source, Name),
        Output = filename:join(Target, Name),
        case filelib:is_dir(Input) of
            true -> snapshot_tree(Input, Output, Extensions);
            false ->
                case lists:member(filename:extension(Name), Extensions) of
                    false -> ok;
                    true ->
                        {ok, Bytes} = file:read_file(Input),
                        ok = file:write_file(Output, Bytes, [exclusive])
                end
        end
    end, lists:sort(Names)).

-doc "Writes source-build.json once, binding every generated/copied input by SHA-256. Units supply entry points, imports, schedules and RTL lists; metadata is descriptive JSON data and cannot override schema fields. Paths and unique unit directories are checked, but this trusted local build record is not a security boundary or hardware qualification.".
-spec finish(file:filename(), [unit()], map()) -> map().
finish(Output, Units, Metadata) ->
    Directories = [maps:get(directory, U) || U <- Units],
    case length(Directories) =:= length(lists:usort(Directories)) of
        true -> ok;
        false -> error(duplicate_unit_directory)
    end,
    lists:foreach(fun(Unit) -> check_unit(Output, Unit) end, Units),
    Roles = lists:usort([maps:get(role, U) || U <- Units]),
    Rtl = maps:from_list([{Role, lists:append([maps:get(rtl, U) || U <- Units,
        maps:get(role, U) =:= Role])} || Role <- Roles]),
    Manifest = #{version => 1, metadata => Metadata, units => Units, rtl => Rtl,
        inputs => [#{file => unicode:characters_to_binary(P), sha256 => digest(filename:join(Output, P))}
            || P <- files(Output)], eligible => false, native_measured => false},
    ok = file:write_file(filename:join(Output, "source-build.json"), json:encode(Manifest), [exclusive]),
    Manifest.

%% Validate paths before freezing the build; products need not exist yet.
-spec check_unit(file:filename(), unit()) -> ok.
check_unit(Output, #{role := Role, directory := Directory, source := Source,
        output := Product, dslx_path := Imports, rtl := Rtl}) ->
    lists:foreach(fun relative/1, [Role, Directory, Source, Product | Imports ++ Rtl]),
    true = filelib:is_regular(filename:join(Output, Source)),
    lists:foreach(fun(P) -> true = filelib:is_dir(filename:join(Output, P)) end, [Role, Directory | Imports]),
    ok.

%% Reject escaping spellings rather than silently rewriting manifest identities.
-spec relative(file:filename_all()) -> file:filename_all().
relative(Path) ->
    Parts = filename:split(Path),
    case filename:pathtype(Path) =:= relative andalso Parts =/= [] andalso
            not lists:any(fun(P) -> P =:= ".." orelse P =:= <<"..">> end, Parts) of
        true -> Path;
        false -> error({nonrelative_bundle_path, Path})
    end.

%% Stable recursive enumeration makes source identity independent of directory order.
-spec files(file:filename()) -> [string()].
files(Directory) ->
    {ok, Names} = file:list_dir(Directory),
    lists:append([case filelib:is_dir(filename:join(Directory, Name)) of
        true -> [filename:join(Name, Child) || Child <- files(filename:join(Directory, Name))];
        false -> [Name]
    end || Name <- lists:sort(Names)]).

%% Bind bytes without making a compiler-equivalence or native-performance claim.
-spec digest(file:filename()) -> binary().
digest(Path) ->
    {ok, Bytes} = file:read_file(Path),
    binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
