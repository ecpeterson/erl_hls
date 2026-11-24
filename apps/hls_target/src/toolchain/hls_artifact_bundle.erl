-module(hls_artifact_bundle).
-moduledoc """
Portable generated-source packaging shared by hls_compile and downstream build frontends. Opens fresh bundles, snapshots support trees and freezes a hashed source-build.json for the external tool driver. Clients supply emission and scheduling policy; this module does not invoke XLS.
""".
%% Fresh bundle construction and publication.
-export([open/1, snapshot/2, finish/3, finish/4]).
%% Shared type contracts.
-export_type([unit/0, library/0, provenance/0]).

-doc "One external compilation unit. All paths are relative to the bundle; codegen_flags are literal XLS arguments supplied by the emitter, never shell text. Each unit needs its own directory for intermediates.".
-type unit() :: #{
    role := binary(),
    directory := binary(),
    source := binary(),
    top := binary(),
    module := binary(),
    output := binary(),
    dslx_path := [binary()],
    codegen_flags := [binary()],
    rtl := [binary()]
}.
-doc "A source tree, its relative bundle destination and the file extensions to copy recursively.".
-type library() :: {file:filename(), string(), [string()]}.

-doc "Source recipe correlation. Unplanned bundles remain valid compiler inputs; implementation_plan binds one logical system, proposed plan and checked target projection by lowercase SHA-256 identity.".
-type provenance() ::
    #{kind := unplanned}
    | #{
        kind := implementation_plan,
        logical_system_sha256 := binary(),
        implementation_plan_sha256 := binary(),
        target_projection_sha256 := binary()
    }.

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
    lists:foreach(
        fun({Source, Relative, Extensions}) ->
            snapshot_tree(Source, filename:join(Output, relative(Relative)), Extensions)
        end,
        Libraries
    ).

%% Import directories are part of the source tree even when no selected file lies below them.
-spec snapshot_tree(file:filename(), file:filename(), [string()]) -> ok.
snapshot_tree(Source, Target, Extensions) ->
    {ok, Names} = file:list_dir(Source),
    ok = filelib:ensure_dir(filename:join(Target, "placeholder")),
    lists:foreach(
        fun(Name) ->
            Input = filename:join(Source, Name),
            Output = filename:join(Target, Name),
            case filelib:is_dir(Input) of
                true ->
                    snapshot_tree(Input, Output, Extensions);
                false ->
                    case lists:member(filename:extension(Name), Extensions) of
                        false ->
                            ok;
                        true ->
                            {ok, Bytes} = file:read_file(Input),
                            ok = file:write_file(Output, Bytes, [exclusive])
                    end
            end
        end,
        lists:sort(Names)
    ).

-doc "Writes an unplanned source-build.json through finish/4. Use finish/4 when a checked implementation plan selected the target projection.".
-spec finish(file:filename(), [unit()], map()) -> map().
finish(Output, Units, Metadata) ->
    finish(Output, Units, Metadata, #{kind => unplanned}).

-doc "Writes source-build.json once, binding every generated/copied input and exact optional plan correlation by SHA-256. Units supply entry points, imports, schedules and RTL lists; metadata is descriptive JSON data and cannot override schema fields. Paths, provenance and unique unit directories are checked, but this trusted local build record is not a security boundary or hardware qualification.".
-spec finish(file:filename(), [unit()], map(), provenance()) -> map().
finish(Output, Units, Metadata, Provenance) ->
    ok = validate_provenance(Provenance),
    Directories = [maps:get(directory, U) || U <- Units],
    case length(Directories) =:= length(lists:usort(Directories)) of
        true -> ok;
        false -> error(duplicate_unit_directory)
    end,
    lists:foreach(fun(Unit) -> check_unit(Output, Unit) end, Units),
    Roles = lists:usort([maps:get(role, U) || U <- Units]),
    Rtl = maps:from_list([
        {Role,
            lists:append([
                maps:get(rtl, U)
             || U <- Units,
                maps:get(role, U) =:= Role
            ])}
     || Role <- Roles
    ]),
    Manifest = #{
        version => 2,
        provenance => Provenance,
        metadata => Metadata,
        units => Units,
        rtl => Rtl,
        inputs => [
            #{file => unicode:characters_to_binary(P), sha256 => digest(filename:join(Output, P))}
         || P <- files(Output)
        ],
        eligible => false,
        native_measured => false
    },
    ok = file:write_file(filename:join(Output, "source-build.json"), json:encode(Manifest), [
        exclusive
    ]),
    Manifest.

%% Accept only the closed recipe-correlation vocabulary and exact lowercase SHA-256 text.
-spec validate_provenance(term()) -> ok.
validate_provenance(#{kind := unplanned} = Provenance) when map_size(Provenance) =:= 1 ->
    ok;
validate_provenance(
    #{
        kind := implementation_plan,
        logical_system_sha256 := LogicalSystem,
        implementation_plan_sha256 := Plan,
        target_projection_sha256 := Projection
    } = Provenance
) when map_size(Provenance) =:= 4 ->
    case lists:all(fun sha256/1, [LogicalSystem, Plan, Projection]) of
        true -> ok;
        false -> error({invalid_build_provenance, Provenance})
    end;
validate_provenance(Provenance) ->
    error({invalid_build_provenance, Provenance}).

%% Lowercase hexadecimal avoids multiple textual identities for the same digest.
-spec sha256(term()) -> boolean().
sha256(Value) when is_binary(Value), byte_size(Value) =:= 64 ->
    lists:all(
        fun(Byte) ->
            (Byte >= $0 andalso Byte =< $9) orelse (Byte >= $a andalso Byte =< $f)
        end,
        binary_to_list(Value)
    );
sha256(_) ->
    false.

%% Validate paths before freezing the build; products need not exist yet.
-spec check_unit(file:filename(), unit()) -> ok.
check_unit(Output, #{
    role := Role,
    directory := Directory,
    source := Source,
    output := Product,
    dslx_path := Imports,
    rtl := Rtl
}) ->
    lists:foreach(fun relative/1, [Role, Directory, Source, Product | Imports ++ Rtl]),
    true = filelib:is_regular(filename:join(Output, Source)),
    lists:foreach(fun(P) -> true = filelib:is_dir(filename:join(Output, P)) end, [
        Role, Directory | Imports
    ]),
    ok.

%% Reject escaping spellings rather than silently rewriting manifest identities.
-spec relative(file:filename_all()) -> file:filename_all().
relative(Path) ->
    Parts = filename:split(Path),
    case
        filename:pathtype(Path) =:= relative andalso Parts =/= [] andalso
            not lists:any(fun(P) -> P =:= ".." orelse P =:= <<"..">> end, Parts)
    of
        true -> Path;
        false -> error({nonrelative_bundle_path, Path})
    end.

%% Stable recursive enumeration makes source identity independent of directory order.
-spec files(file:filename()) -> [string()].
files(Directory) ->
    {ok, Names} = file:list_dir(Directory),
    lists:append([
        case filelib:is_dir(filename:join(Directory, Name)) of
            true -> [filename:join(Name, Child) || Child <- files(filename:join(Directory, Name))];
            false -> [Name]
        end
     || Name <- lists:sort(Names)
    ]).

%% Bind bytes without making a compiler-equivalence or native-performance claim.
-spec digest(file:filename()) -> binary().
digest(Path) ->
    {ok, Bytes} = file:read_file(Path),
    binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
