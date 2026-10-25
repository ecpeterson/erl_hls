-module(hls_protocol_boundary).
-moduledoc "Builds one application-facing frame stream per declared external endpoint around a fresh source network.".
-export([plan/2, descriptor/1, write/2, write/3, emit/1, emit/2]).
-export_type([plan/0, options/0, descriptor/0, manifest/0, result/0, output/0]).

-doc "Boundary composition accepts the network's activation and inspection options without changing source or placement.".
-type options() :: hls_source_config:network_options().

-doc "The checked external streams, pass-through ports and arbitration costs before emission.".
-type descriptor() :: xls_protocol_boundary:descriptor().

-doc "The final boundary interface, including its required source hash and corresponding inspection evidence.".
-type manifest() :: xls_protocol_boundary:manifest().

-doc "Boundary files paired with their concrete final boundary/transport result.".
-type output() :: hls_generated_files:output(result()).

%% The network plan owns source wiring; the boundary layout owns endpoint arbitration.
-record(plan, {network :: hls_protocol_network:plan(), layout :: xls_protocol_boundary:plan()}).

-doc "A checked external-boundary composition from plan/2. Retain unchanged in process; it grants no capacity, progress or device admission.".
-opaque plan() :: #plan{}.

-doc "The emitted boundary manifest and its source transport descriptor; both belong to the same in-process build.".
-type result() :: #{boundary := manifest(), transport := hls_protocol_transport:descriptor()}.

-doc "Builds hls_protocol_network from the same trusted config, then merges its independent producer streams by declared external endpoint. Round-robin arbitration holds its chosen producer throughout a stall and preserves per-sender order; there is no cross-sender chronology. Empty endpoints remain invalid; singleton endpoints add no state. Startup/host/start/fault pins pass through unchanged. Requires a fresh directory and at most 256 producers per endpoint; unsupported fan-in creates no output. I/O failures retain partial output. An unchanged composition plan may also be written directly. Returns a bound manifest with eligibility false. Compilation, application framing and progress admission remain separate.".
-spec write(hls_source_config:boundary() | file:filename() | plan(), file:filename()) -> manifest().
write(Config, Directory) ->
    #{boundary := Boundary} = hls_generated_files:write(emit(Config), Directory),
    Boundary.

-doc "Writes emit/2's planned boundary bundle to a fresh directory and returns its boundary/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), options(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a boundary bundle from a trusted source config map or a filename containing one map. Source paths remain relative to the caller. Preparation loads sources and invokes trusted constructors; an unchanged plan/2 value skips preparation and layout checks. Generation returns relative filenames with IO data and named boundary/transport descriptors without writing output.".
-spec emit(hls_source_config:boundary() | file:filename() | plan()) -> output().
emit(#plan{network = NetworkPlan, layout = Layout}) ->
    #{files := NetworkFiles, result := #{network := #{inspection := Inspection}, transport := Transport}} =
        hls_protocol_network:emit(NetworkPlan),
    #{files := BoundaryFiles, result := Boundary} = xls_protocol_boundary:emit(Layout, Inspection),
    #{files => hls_generated_files:merge([NetworkFiles, BoundaryFiles]),
      result => #{boundary => Boundary, transport => Transport}};
emit(Config) when is_map(Config) ->
    emit(hls_protocol_transport:plan(Config), maps:with([activation, inspection], Config));
emit(Filename) -> emit(hls_source_config:read(Filename)).

-doc "Checks the source network and groups its producer ports by external endpoint before rendering composition hardware. Options accepts activation/inspection. Rejects more than 256 producers per endpoint; computes pass-through ports and arbitration state without reading templates. The input transport retains checked source snapshots and receiver layouts.".
-spec plan(hls_protocol_transport:build(), options()) -> plan().
plan(Build, Options) ->
    NetworkPlan = hls_protocol_network:plan(Build, Options),
    Network = #{externals := Externals, boundaries := Boundaries} = hls_protocol_network:descriptor(NetworkPlan),
    Groups = [group(E, Boundaries) || E <- Externals],
    #plan{network = NetworkPlan, layout = xls_protocol_boundary:plan(#{network => Network, externals => Groups})}.

-doc "Returns the checked boundary ports, endpoint groups, state costs and inspection mode (none or process), before rendering. Generated-byte hashes and the inspection catalog belong to emit/1's final manifest. Treat this descriptor as read-only.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{layout = Layout}) -> xls_protocol_boundary:descriptor(Layout).

-doc "Plans and emits the source network and external arbiters. Equivalent to emit(plan(Build, Options)); returns relative files and final boundary/transport descriptors. Options accepts activation/inspection only; source and placement stay fixed.".
-spec emit(hls_protocol_transport:build(), options()) -> output().
emit(Build, Options) -> emit(plan(Build, Options)).

%% Every producer belongs to one declared endpoint; an unused endpoint needs no arbiter.
-spec group(xls_protocol_network:external(), [xls_protocol_network:producer()]) -> xls_protocol_boundary:group().
group(E=#{index:=I},Boundaries) ->
    Members=[B||B=#{external_index:=J}<-Boundaries,J=:=I],N=length(Members),
    case N=<256 of
        true->E#{members=>Members,index_bits=>max(1,ceil(math:log2(max(1,N)))),
            state_bits=>case N>1 of true->2*max(1,ceil(math:log2(N)))+1;false->0 end};
        false->error({unsupported_external_fanin,I,N})
    end.
