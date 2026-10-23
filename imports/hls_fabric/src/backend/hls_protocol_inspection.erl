-module(hls_protocol_inspection).
-moduledoc "Source-bound passive process metadata for the existing endpoint-2 inspection service.".
-export([mode/1, write/2]).

-doc "Accepts none or process; rejects unsupported inspection before source compilation.".
-spec mode(term()) -> none | process.
mode(none) -> none;
mode(process) -> process;
mode(Other) -> error({unsupported_protocol_inspection,Other}).

-doc "Writes passive DSLX observation functions, a fingerprinted JSON manifest and a trusted local catalog beside a fresh network. Reads committed machine metadata only, with no new actor state or application backpressure. Collection fields use the common 128-bit reply policy; payloads, mailbox occupancy and history are excluded. The caller must connect inspect_address/value to the unchanged topology debug service under the same reset.".
-spec write(map(),file:filename()) -> map().
write(#{bundle:=#{topology:=#{actors:=Actors},modules:=Modules},receivers:=Receivers},Directory) ->
    Rows=[#{index=>I,id=>Id,module=>M}||{I,#{id:=Id,module:=M}}<-lists:enumerate(0,Actors)],
    Resources=[resource(A,maps:get(M,Modules))||A=#{module:=M}<-Rows],
    Source=[observation(R,maps:get(M,Modules))||R=#{module:=M}<-Receivers],
    ok=file:write_file(filename:join(Directory,"process_observation.x"),Source,[exclusive]),
    Manifest0=json(#{schema=>5,resources=>Resources,probes=>[],catalogue_sha256=>digest(term_to_binary(Rows,[deterministic])),
        inspection=>#{scope=>process,coherence=>one_process_pre_edge,history=>unavailable,
            sampling=>query_service_acceptance_edge,transport_stalls=>excluded},
        source_plans=>maps:map(fun(_,#{plan:=P})->maps:with([source,source_sha256,artifact_sha256,planner_md5],xls_statem_plan:manifest(P)) end,Modules),
        dslx_sha256=>digest(iolist_to_binary(Source)),
        limits=>[<<"Separate queries are not atomic together.">>,<<"No mailbox counts, payloads or continuous event history.">>]}),
    Manifest=Manifest0#{<<"fingerprint">>=>hls_topology_debug:manifest_fingerprint(Manifest0)},
    ok=file:write_file(filename:join(Directory,"inspection.json"),json:encode(Manifest),[exclusive]),
    ok=file:write_file(filename:join(Directory,"inspection.etf"),term_to_binary(#{actors=>Rows,manifest=>Manifest},[deterministic]),[exclusive]),
    Manifest.

%% Resource order is the exact normalized actor order, including composite logical identities.
-spec resource(map(),map()) -> map().
resource(#{index:=I,id:=Id,module:=M},#{spec:=Spec}) ->
    Collection=xls_actor_observation:collection(Spec),Layout=xls_actor_observation:layout(Collection),
    Base=#{id=>I,kind=>actor,name=>iolist_to_binary(["owner/",integer_to_list(I)]),owner_index=>I,
        logical_key=>xls_actor_debug:actor_key(Id),logical_name=>iolist_to_binary(io_lib:format("~0tp",[Id])),
        role=>M,phases=>maps:get(phases,Spec),failures=>xls_actor_debug:failures(maps:get(failure_sites,Spec)),
        width=>case Collection of none->26;_->56+maps:get(width,maps:get(reduction,Layout)) end},
    case Collection of none->Base;#{sites:=Sites}->Base#{reduction=>(maps:get(reduction,Layout))#{
        sites=>[maps:with([id,phase,name,population,kind],S)||S<-Sites]}} end.

%% Projection reads declared raw-machine offsets, never private action or collection payload data.
-spec observation(map(),map()) -> iodata().
observation(#{index:=I,manifest:=#{machine_layout:=ML,machine_bits:=Width}},#{spec:=Spec}) ->
    Layout=xls_actor_observation:layout(xls_actor_observation:collection(Spec)),
    Fields=maps:get(fields,maps:get(reduction,Layout,#{fields=>#{}})),
    Pieces=["(bits[128]:1 << u32:25)",shift(slice(maps:get(phase,ML)),0),
        shift(slice(maps:get(enter_pending,ML)),8),shift(slice(maps:get(failure,ML)),9)]++
        [shift(progress(Name,Bits,Spec,ML),At)||{Name,#{observation_offset:=At,width:=Bits}}<-lists:sort(maps:to_list(Fields)),Bits>0],
    ["// One coherent committed process observation; initialization/reset mask all metadata.\n",
     "pub fn observe_",n(I),"(raw: bits[",n(Width),"], initialized: bool, reset: bool) -> bits[128] {\n",
     "if reset || !initialized { bits[128]:0 } else { ",lists:join(" | ",Pieces)," } }\n"].

%% Gather metadata supersedes scalar metadata only while its source status is active.
-spec progress(atom(),pos_integer(),map(),map()) -> iodata().
progress(Name,Width,#{reductions:=R,gathers:=G},ML) ->
    Scalar=case R of none->["bits[",n(Width),"]:0"];_->field(Name,Width,reduction,xls_statem_reduction_ir:packed_layout(R),ML) end,
    case G of none->Scalar;#{sites:=[#{population:=#{size:=C}}]}->
        Layout=maps:from_list([{K,#{offset=>O,width=>W}}||{K,O,W}<-[{status,0,2},{site,2,8},{key,10,32},{remaining,42,8},{expected,50,C},{seen,50+C,C},{failure,50+2*C,16}]]),
        Gather=field(Name,Width,gather,Layout,ML),
        Count=case R of none->0;#{sites:=Sites}->length(Sites) end,
        Value=case Name of site->["(",Gather," + bits[",n(Width),"]:",n(Count),")"];_->Gather end,
        ["(if ",field(status,2,gather,Layout,ML)," != u2:0 { ",Value," } else { ",Scalar," })"]
    end.

%% Absent membership fields are zero; widths follow the common bounded observation ABI.
-spec field(atom(),pos_integer(),atom(),map(),map()) -> iodata().
field(Name,Width,Kind,Layout,ML) ->
    case maps:find(Name,Layout) of
        error->["bits[",n(Width),"]:0"];
        {ok,#{width:=0}}->["bits[",n(Width),"]:0"];
        {ok,#{offset:=At,width:=Bits}}->
            #{offset:=Base}=maps:get(Kind,ML),
            ["(",slice(#{offset=>Base+At,width=>Bits})," as bits[",n(Width),"])"]
    end.

%% Slices are compiler-owned dimensions; no source text is interpreted as a wire expression.
-spec slice(map()) -> iodata().
slice(#{offset:=At,width:=Bits}) -> ["raw[",n(At),"+:bits[",n(Bits),"]]"].
%% Cast before shifting so narrow metadata is never truncated at its destination offset.
-spec shift(iodata(),non_neg_integer()) -> iodata().
shift(Value,At) -> ["((",Value," as bits[128]) << u32:",n(At),")"].
%% Normalize JSON before computing the shared canonical fingerprint.
-spec json(map()) -> map().
json(Value) -> json:decode(iolist_to_binary(json:encode(Value))).
%% Stable byte identities bind metadata and its trusted local catalog.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256,Bytes),lowercase).
%% Only validated static widths/indices enter generated DSLX.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
