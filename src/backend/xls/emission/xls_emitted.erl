-module(xls_emitted).
-moduledoc "Finalizes an actor/server DSLX module and its generated imports with one failure codebook allocated from their structured references. Renderers create these artifacts; build clients write their files and debug builders consume their sites. Readable source-origin comments are embedded in each module at finalization. Imported modules belong to the enclosing artifact, not independent codebooks. Digests detect accidental replacement across build boundaries, not authenticity or hardware equivalence.".
%% Allocate references and render a complete module with its generated imports.
-export([new/2, new/3, new/4]).
%% Read or write emitted files and validate their source-failure metadata.
-export([bytes/1, dependencies/1, write/2, sites/1, sites/2]).
%% Retain metadata when a backend wraps an existing artifact.
-export([with_bytes/2]).
-export_type([artifact/0, module_document/0]).

-doc "A completed module, generated imports and failure sites under one consistency seal. Construct through new/2,3,4; use with_bytes/2 only for trusted composition which preserves imports and failure semantics.".
-opaque artifact() :: #{
    dslx := binary(),
    dependencies := #{string() => binary()},
    sites := [xls_failure_sites:site()],
    sha256 := binary()
}.

-doc "One generated import before final failure allocation. Its preamble precedes the declarations used by its body.".
-type module_document() :: #{preamble := xls_dslx:value(), body := xls_dslx:value()}.

-doc "Allocates retained failure references once, renders the complete document, and binds its codebook to the resulting bytes.".
-spec new([xls_failure_sites:location()], xls_dslx:value()) -> artifact().
new(Locations, Document) -> new(Locations, [], Document).

-doc "Finalizes a complete module, placing failure declarations after its preamble. Allocation visits both preamble and body before either is rendered.".
-spec new([xls_failure_sites:location()], xls_dslx:value(), xls_dslx:value()) -> artifact().
new(Locations, Preamble, Body) -> new(Locations, Preamble, Body, #{}).

-doc "Allocates one codebook across the main module and generated imports, then declares each module's referenced sites with those shared codes. Dependency keys are canonical relative .x paths below the eventual main file's directory; each import belongs to this artifact's source closure and codebook.".
-spec new(
    [xls_failure_sites:location()],
    xls_dslx:value(),
    xls_dslx:value(),
    #{string() => module_document()}
) -> artifact().
new(Locations, Preamble, Body, Modules) ->
    lists:foreach(fun dependency_path/1, maps:keys(Modules)),
    Main = #{preamble => Preamble, body => Body},
    Sites = xls_failure_sites:allocate(Locations, [
        document(Main) | [document(M) || {_Path, M} <- lists:sort(maps:to_list(Modules))]
    ]),
    Dependencies = maps:map(fun(_Path, Module) -> render(Module, Sites, Locations) end, Modules),
    seal(render(Main, Sites, Locations), Dependencies, Sites).

%% Allocation sees every module before any declaration receives its numeric value.
-spec document(module_document()) -> xls_dslx:value().
document(#{preamble := Preamble, body := Body}) -> [Preamble, Body].

%% A module declares only its own references without renumbering the shared codebook.
-spec render(module_document(), [xls_failure_sites:site()], [xls_failure_sites:location()]) ->
    binary().
render(Module = #{preamble := Preamble, body := Body}, Sites, Locations) ->
    Referenced = [
        maps:remove(code, S)
     || S <- xls_failure_sites:allocate(Locations, document(Module))
    ],
    LocalSites = [S || S <- Sites, lists:member(maps:remove(code, S), Referenced)],
    xls_dslx:render_annotated([Preamble, xls_failure_sites:declarations(LocalSites), Body]).

-doc "Returns final DSLX bytes after checking their codebook consistency seal.".
-spec bytes(artifact()) -> binary().
bytes(Module = #{dslx := Bytes}) ->
    ok = validate(Module),
    Bytes.

-doc "Returns generated import paths and bytes after checking the seal over the complete artifact. Paths are relative to the main module's directory; the main module itself is returned by bytes/1.".
-spec dependencies(artifact()) -> #{string() => binary()}.
dependencies(Module = #{dependencies := Dependencies}) ->
    ok = validate(Module),
    Dependencies.

-doc "Writes the annotated main module and all generated imports beside it, creating parent directories and replacing existing generated files. Validates the complete artifact and rejects escaping paths or a dependency named like the main file before writing. Partial output is retained on filesystem errors; compiler support libraries are supplied separately.".
-spec write(artifact(), file:filename()) -> ok.
write(Module = #{dslx := Bytes, dependencies := Dependencies}, MainFilename) ->
    ok = validate(Module),
    lists:foreach(fun dependency_path/1, maps:keys(Dependencies)),
    case maps:is_key(filename:basename(MainFilename), Dependencies) of
        true -> error({dependency_overwrites_main, MainFilename});
        false -> ok
    end,
    Directory = filename:dirname(MainFilename),
    lists:foreach(
        fun({Path, Contents}) ->
            Target = filename:join(Directory, Path),
            ok = filelib:ensure_dir(Target),
            ok = file:write_file(Target, Contents)
        end,
        lists:sort(maps:to_list(Dependencies))
    ),
    ok = filelib:ensure_dir(MainFilename),
    file:write_file(MainFilename, Bytes).

%% Keep emitted identities canonical and below the enclosing module's directory.
-spec dependency_path(string()) -> ok.
dependency_path(Path) ->
    Parts = filename:split(Path),
    case
        filename:pathtype(Path) =:= relative andalso Parts =/= [] andalso
            not lists:any(fun(P) -> P =:= "." orelse P =:= ".." end, Parts) andalso
            filename:join(Parts) =:= Path andalso filename:extension(Path) =:= ".x"
    of
        true -> ok;
        false -> error({invalid_dependency_path, Path})
    end.

-doc "Returns a freshly emitted module's codebook after checking its seal and canonical allocation. Use sites/2 when accepting an artifact against independently loaded source metadata.".
-spec sites(artifact()) -> [xls_failure_sites:site()].
sites(Module = #{sites := Sites}) ->
    ok = validate(Module),
    case xls_failure_sites:number([maps:remove(code, S) || S <- Sites]) =:= Sites of
        true -> Sites;
        false -> error(failure_codebook_mismatch)
    end.

-doc "Returns the allocated codebook after checking emitted bytes, canonical codes and independent source locations.".
-spec sites(artifact(), [xls_failure_sites:location()]) -> [xls_failure_sites:site()].
sites(Module = #{sites := Sites}, Locations) ->
    ok = validate(Module),
    ok = xls_failure_sites:validate_sites(Locations, Sites),
    Sites.

-doc "Rebinds an already checked codebook to trusted composed bytes. The caller must preserve the failure-code semantics and placement of embedded source annotations, including imported owners; this is not an API for accepting edited external artifacts.".
-spec with_bytes(artifact(), iodata()) -> artifact().
with_bytes(Module = #{sites := Sites, dependencies := Dependencies}, Bytes) ->
    ok = validate(Module),
    seal(iolist_to_binary(Bytes), Dependencies, Sites).

%% Keep all emitted bytes and their shared codebook under one deterministic identity.
-spec seal(binary(), #{string() => binary()}, [xls_failure_sites:site()]) -> artifact().
seal(Bytes, Dependencies, Sites) ->
    #{
        dslx => Bytes,
        dependencies => Dependencies,
        sites => Sites,
        sha256 => digest(Bytes, Dependencies, Sites)
    }.

%% An opaque value can still arrive from a modified sidecar or external caller.
-spec validate(artifact()) -> ok.
validate(#{dslx := Bytes, dependencies := Dependencies, sites := Sites, sha256 := Hash}) ->
    case digest(Bytes, Dependencies, Sites) =:= Hash of
        true -> ok;
        false -> error(emitted_module_mismatch)
    end.

%% This integrity boundary is local to the trusted build, not cryptographic authorship.
-spec digest(binary(), #{string() => binary()}, [xls_failure_sites:site()]) -> binary().
digest(Bytes, Dependencies, Sites) ->
    crypto:hash(sha256, term_to_binary({Bytes, Dependencies, Sites}, [deterministic])).
