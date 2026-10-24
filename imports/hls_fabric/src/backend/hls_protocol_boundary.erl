-module(hls_protocol_boundary).
-moduledoc "Builds one application-facing frame stream per declared external endpoint around a fresh source network.".
-export([write/2, write/3, emit/1, emit/2]).
-export_type([result/0]).

-doc "The emitted boundary manifest and its source transport descriptor; both belong to the same in-process build.".
-type result() :: #{boundary := map(), transport := map()}.

-doc "Builds hls_protocol_network from the same trusted config, then merges its independent producer streams by declared external endpoint. Round-robin arbitration holds its chosen producer throughout a stall and preserves per-sender order; there is no cross-sender chronology. Empty endpoints remain invalid; singleton endpoints add no state. Startup/host/start/fault pins pass through unchanged. Requires a fresh directory and at most 256 producers per endpoint; unsupported fan-in creates no output. I/O failures retain partial output. Returns a bound manifest with eligibility false. Compilation, application framing and progress admission remain separate.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    #{boundary := Boundary} = hls_generated_files:write(emit(Config), Directory),
    Boundary.

-doc "Writes emit/2's planned boundary bundle to a fresh directory and returns its boundary/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), map(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a boundary bundle from a trusted source config map or a filename containing one map. Source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors; generation returns relative filenames with IO data and named boundary/transport descriptors without writing output.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config) when is_map(Config) ->
    emit(hls_protocol_transport:plan(Config), maps:with([activation, inspection], Config));
emit(Filename) -> emit(hls_source_config:read(Filename)).

-doc "Generates a planned source transport through its network and external arbiters. Options supplies activation/inspection; the unchanged in-process Build fixes source and placement. Returns relative filenames with IO data and boundary/transport descriptors without writing output. Unsupported fan-in is rejected during generation; templates are read as inputs.".
-spec emit(hls_protocol_transport:build(), map()) -> hls_generated_files:output().
emit(Build, Options) ->
    #{files := NetworkFiles,
      result := #{network := Network = #{externals := Externals, boundaries := Boundaries}, transport := Transport}} =
        hls_protocol_network:emit(Build, Options),
    Groups = [group(E, Boundaries) || E <- Externals],
    #{files := BoundaryFiles, result := Boundary} = xls_protocol_boundary:emit(#{network => Network, externals => Groups}),
    #{files => hls_generated_files:merge([NetworkFiles, BoundaryFiles]),
      result => #{boundary => Boundary, transport => Transport}}.

%% Every producer belongs to one declared endpoint; an unused endpoint needs no arbiter.
-spec group(map(),[map()]) -> map().
group(E=#{index:=I},Boundaries) ->
    Members=[B||B=#{external_index:=J}<-Boundaries,J=:=I],N=length(Members),
    case N=<256 of
        true->E#{members=>Members,index_bits=>max(1,ceil(math:log2(max(1,N)))),
            state_bits=>case N>1 of true->2*max(1,ceil(math:log2(N)))+1;false->0 end};
        false->error({unsupported_external_fanin,I,N})
    end.
