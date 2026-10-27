-module(xls_emitted).
-moduledoc "Final DSLX bytes and the codebook allocated from their structured lowering. Digests detect accidental replacement across build boundaries; they are not signatures.".
-export([new/2, new/3, bytes/1, sites/1, sites/2, with_bytes/2]).
-export_type([artifact/0]).

-doc "A completed module with a consistency seal over both emitted bytes and allocated failure sites. Construct through new/2; use with_bytes/2 only for trusted composition which preserves failure semantics.".
-opaque artifact() :: #{dslx := binary(), sites := [xls_failure_sites:site()], sha256 := binary()}.

-doc "Allocates retained failure references once, renders the complete document, and binds its codebook to the resulting bytes.".
-spec new([xls_failure_sites:location()], xls_dslx:value()) -> artifact().
new(Locations, Document) -> new(Locations, [], Document).

-doc "Finalizes a complete module, placing failure declarations after its preamble. Allocation visits both preamble and body before either is rendered.".
-spec new([xls_failure_sites:location()], xls_dslx:value(), xls_dslx:value()) -> artifact().
new(Locations, Preamble, Body) ->
    Sites = xls_failure_sites:allocate(Locations, [Preamble, Body]),
    Bytes = iolist_to_binary([xls_dslx:render(Preamble), xls_failure_sites:declarations(Sites),
        xls_dslx:render(Body)]),
    seal(Bytes, Sites).

-doc "Returns final DSLX bytes after checking their codebook consistency seal.".
-spec bytes(artifact()) -> binary().
bytes(Module = #{dslx := Bytes}) ->
    ok = validate(Module),
    Bytes.

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

-doc "Rebinds an already checked codebook to trusted composed bytes. The caller must preserve the failure-code semantics, including imported owners; this is not an API for accepting edited external artifacts.".
-spec with_bytes(artifact(), iodata()) -> artifact().
with_bytes(Module = #{sites := Sites}, Bytes) ->
    ok = validate(Module),
    seal(iolist_to_binary(Bytes), Sites).

%% Keep the paired bytes and codebook under one deterministic identity.
-spec seal(binary(), [xls_failure_sites:site()]) -> artifact().
seal(Bytes, Sites) -> #{dslx => Bytes, sites => Sites, sha256 => digest(Bytes, Sites)}.

%% An opaque value can still arrive from a modified sidecar or external caller.
-spec validate(artifact()) -> ok.
validate(#{dslx := Bytes, sites := Sites, sha256 := Hash}) ->
    case digest(Bytes, Sites) =:= Hash of
        true -> ok;
        false -> error(emitted_module_mismatch)
    end.

%% This integrity boundary is local to the trusted build, not cryptographic authorship.
-spec digest(binary(), [xls_failure_sites:site()]) -> binary().
digest(Bytes, Sites) -> crypto:hash(sha256, term_to_binary({Bytes, Sites}, [deterministic])).
