-module(xls_protocol_network).
-moduledoc "Connects source-bound receivers and transport using the explicit clock transition in protocol_network.x.in. Erlang elaborates heterogeneous connections; DSLX retains the observe, select and commit order.".
-export([plan/1, descriptor/1, emit/2]).
-export_type([plan/0]).

%% Packed interface order is shared by DSLX, the pin adapter and the manifest.
-type clock_port() :: {string(), pos_integer()}.
%% One receiver's authoritative incoming mask spans and optional host retirement slot.
-type receiver_wiring() :: #{index := non_neg_integer(),
    links := [hls_protocol_inbox:link_binding()], host_slot := none | non_neg_integer()}.

%% Checked wiring and interface order are retained independently of emitted files.
-record(plan, {input :: map(), wiring :: [receiver_wiring()],
    inputs :: [clock_port()], outputs :: [clock_port()],
    descriptor :: map(), components :: [string()]}).

-doc "An unchanged in-process network composition from plan/1. Retains checked receiver wiring, packed ports and source descriptors without rendering network hardware or assigning its byte hashes. It is not a serialized input format or hardware admission.".
-opaque plan() :: #plan{}.

-doc "Plans network composition from hls_protocol_transport's descriptor with checked activation/inspection modes. Validates receiver-owned inbox spans against source/link identities, fixes interface order and derives static metadata without reading templates or emitting files. Sources, placement and capability checks belong to the enclosing builder.".
-spec plan(map()) -> plan().
plan(Input) ->
    Transport = Input#{arithmetic => maps:get(arithmetic, Input, [])},
    #{fabric := Fabric, receivers := Receivers} = Transport,
    Wiring = wiring(Fabric, Receivers),
    {Inputs, Outputs} = ports(Transport),
    #plan{input = Transport, wiring = Wiring, inputs = Inputs, outputs = Outputs,
        descriptor = static_descriptor(Transport, Inputs, Outputs),
        components = component_files(Transport)}.

-doc "Returns the planned interface and static network facts without emission. inspection is none or process; emitted observation evidence and component/source hashes are intentionally absent. Treat this descriptor as read-only.".
-spec descriptor(plan()) -> map().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns network files and a manifest from an unchanged composition plan and exact upstream bytes, without writing output. Adds actual inspection evidence and emitted-byte hashes to the static descriptor. The DSLX template samples old state, selects shared arithmetic, advances receivers and commits transport once. Template reads remain; no capacity, progress or physical qualification is granted.".
-spec emit(plan(), hls_generated_files:files()) -> hls_generated_files:output().
emit(#plan{input = Input, wiring = Wiring, inputs = Inputs, outputs = Outputs,
        descriptor = Descriptor, components = Components}, UpstreamFiles) ->
    {Debug, OptionalFiles} = optional_files(Input),
    Source = render(Input, Wiring, Inputs, Outputs),
    GeneratedFiles = hls_generated_files:merge([OptionalFiles,
        #{"network/network.x" => Source,
          "network/protocol_network.sv" => sv_protocol_ports:emit(
              Inputs, Outputs, "protocol_network", "protocol_network_core")}]),
    ComponentFiles = hls_generated_files:merge([UpstreamFiles, GeneratedFiles]),
    Manifest = Descriptor#{inspection := Debug, dslx_sha256 => hls_generated_files:hash(Source),
        components => [#{file => list_to_binary(File),
            sha256 => hls_generated_files:hash(maps:get(File, ComponentFiles))} || File <- Components]},
    #{files => hls_generated_files:merge([GeneratedFiles,
          #{"network/manifest.json" => json:encode(Manifest)}]), result => Manifest}.

%% Join instance identity once. Inbox attachment, not numeric link order, owns mask layout.
-spec wiring(map(), [map()]) -> [receiver_wiring()].
wiring(#{sources := Sources, links := Links}, Receivers) ->
    Indices = [I || #{index := I} <- Sources],
    true = lists:sort(Indices) =:= lists:usort([I || #{index := I} <- Receivers]),
    true = length(Indices) =:= length(Receivers),
    ByIndex = maps:from_list([{I, Inbox} || #{index := I, manifest := #{inbox := Inbox}} <- Receivers]),
    [begin
        Inbox = #{host := Host} = maps:get(I, ByIndex),
        Bindings = hls_protocol_inbox:link_bindings(Inbox),
        Expected = lists:sort([{K, N} || #{index := K, destination_index := D, slots := N} <- Links, D =:= I]),
        Expected = lists:sort([{K, N} || #{index := K, slots := N} <- Bindings]),
        #{index => I, links => Bindings, host_slot => host_slot(Host)}
    end || I <- Indices].

%% No host slot means this receiver contributes zero to the full-topology retirement mask.
-spec host_slot(map()) -> none | non_neg_integer().
host_slot(#{slots := 0}) -> none;
host_slot(#{slots := 1, offset := Offset}) -> Offset.

%% The optional interfaces have one declaration order, independent of expression rendering.
-spec ports(map()) -> {[clock_port()], [clock_port()]}.
ports(#{inspection := Inspection, activation := Activation, ingress := Ingress,
        fabric := Fabric = #{sources := Sources, boundaries := Boundaries}}) ->
    {RemoteInputs, RemoteOutputs} = xls_protocol_partition:ports(Fabric),
    Inspect = Inspection =:= process,
    Explicit = Activation =:= explicit_start,
    {ControlInputs, ControlOutputs} = hls_protocol_control:ports(Ingress),
    Inputs = [{"reset", 1}] ++ optional(Inspect, [{"inspect_address", 32}]) ++
        optional(Explicit, [{"start_valid", 1}]) ++ ControlInputs ++
        [{boundary(B) ++ "_ready", 1} || B <- Boundaries] ++ RemoteInputs,
    Outputs = [{"startup_done", 1}] ++ optional(Inspect, [{"inspect_value", 128}]) ++
        optional(Explicit, [{"start_ready", 1}, {"running", 1}]) ++ ControlOutputs ++
        lists:append([[{actor(I) ++ "_failure", 16}, {actor(I) ++ "_fault", 1}] || #{index := I} <- Sources]) ++
        lists:append([[{boundary(B) ++ "_valid", 1}, {boundary(B) ++ "_data", W}]
            || B = #{output := #{width := W}} <- Boundaries]) ++ RemoteOutputs,
    {Inputs, Outputs}.

%% Optional implementations are emitted before their bytes enter component hashes.
-spec optional_files(map()) -> {none | map(), hls_generated_files:files()}.
optional_files(Plan = #{inspection := Inspection, ingress := Ingress}) ->
    {Debug, InspectionFiles} = case Inspection of
        process ->
            #{result := Manifest, files := Files} = hls_protocol_inspection:emit(Plan),
            {Manifest, hls_generated_files:prefix("network", Files)};
        none -> {none, #{}}
    end,
    IngressFiles = case Ingress of
        none -> #{};
        _ -> #{"dslx/ingress.x" => xls_protocol_ingress:emit(Ingress)}
    end,
    {Debug, hls_generated_files:merge([InspectionFiles, IngressFiles])}.

%% The template owns sequencing; each slot below supplies only elaborated wiring or an optional component.
-spec render(map(), [receiver_wiring()], [clock_port()], [clock_port()]) -> binary().
render(#{inspection := Inspection, activation := Activation, ingress := Ingress, arithmetic := Arithmetic,
        fabric := Fabric = #{sources := Sources, links := Links, boundaries := Boundaries}}, Wiring, Inputs, Outputs) ->
    Inspect = Inspection =:= process,
    Explicit = Activation =:= explicit_start,
    Host = Ingress =/= none,
    {RemoteInputs, RemoteOutputs} = xls_protocol_partition:ports(Fabric),
    Incoming = [I || #{index := I, direction := incoming} <- maps:get(crossings, Fabric, [])],
    Spans = maps:from_list([{K, At} || #{links := Bs} <- Wiring, #{index := K, offset := At} <- Bs]),
    {ok, Template} = file:read_file(filename:join(code:priv_dir(hls_fabric), "xls/templates/protocol_network.x.in")),
    {ok, Clock} = file:read_file(filename:join(code:priv_dir(hls_fabric), "xls/templates/protocol_network_clock.x.in")),
    xls_template:render(Template, [
        {<<"@@IMPORTS@@">>, imports(Sources, Arithmetic, Inspect, Explicit, Host)},
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@STATE_FIELDS@@">>, state_fields(Sources, Arithmetic, Host, Explicit)},
        {<<"@@STARTUP_DONE@@">>, lists:join(" && ", [[actor(I), "::local_inbox_startup_done(s.", actor(I), ", io.reset)"] || #{index := I} <- Sources])},
        {<<"@@INGRESS_OBSERVE@@">>, optional(Host, "let ingress_offer = ingress::observe(s.ingress, io.reset, startup_done);\n")},
        {<<"@@ACTOR_OBSERVE@@">>, observe(Sources)},
        {<<"@@OFFER_FIELDS@@">>, offer(Sources, Links, Boundaries, RemoteInputs, Spans, Explicit)},
        {<<"@@ARITHMETIC_SELECT@@">>, xls_protocol_arithmetic:steps(Arithmetic)},
        {<<"@@RECEIVER_STEPS@@">>, [receiver(R, Arithmetic) || R <- Wiring]},
        {<<"@@INGRESS_STEP@@">>, ingress_step(Ingress, Wiring)},
        {<<"@@RETIRE_FIELDS@@">>, retire(Links, Spans)},
        {<<"@@ACTIVATION_STEP@@">>, activation_step(Explicit, Host, Sources, Incoming)},
        {<<"@@STATE_UPDATES@@">>, updates(Sources, Arithmetic, Host, Explicit)},
        {<<"@@OBSERVATIONS@@">>, observations(Sources, Boundaries, RemoteOutputs, Inspect, Explicit, Host)},
        {<<"@@CLOCK@@">>, Clock}]).

%% Imports expose exactly the instantiated optional components and receiver owners.
-spec imports([map()], [map()], boolean(), boolean(), boolean()) -> iodata().
imports(Sources, Arithmetic, Inspect, Explicit, Host) ->
    [optional(Arithmetic =/= [], "import protocol_inbox as arithmetic;\n"),
     optional(Inspect, "import process_observation as inspection;\n"),
     optional(Explicit, "import protocol_activation as activation;\n"),
     optional(Host, "import ingress;\n"),
     [["import receiver_", n(I), " as ", actor(I), ";\n"] || #{index := I} <- Sources]].

%% Each native actor retains its own state even when its source definition is shared.
-spec state_fields([map()], [map()], boolean(), boolean()) -> iodata().
state_fields(Sources, Arithmetic, Host, Explicit) ->
    [[[actor(I), ": ", actor(I), "::LocalInboxState,\n"] || #{index := I} <- Sources],
     optional(Host, "ingress: ingress::State,\n"), optional(Explicit, "activation: activation::State,\n"),
     xls_protocol_arithmetic:state(Arithmetic)].

%% Publications and selective-receive eligibility depend only on pre-edge receiver state.
-spec observe([map()]) -> iodata().
observe(Sources) ->
    [["let batch_", n(I), " = ", actor(I), "::local_inbox_batch(s.", actor(I), ", io.reset);\n",
      "let eligible_", n(I), " = ", actor(I), "::local_inbox_eligible(s.", actor(I), ", io.reset);\n"] || #{index := I} <- Sources].

%% Receiver-owned spans slice eligibility in the same order as take and release.
-spec offer([map()], [map()], [map()], [clock_port()], #{non_neg_integer() => non_neg_integer()}, boolean()) -> iodata().
offer(Sources, Links, Boundaries, RemoteInputs, Spans, Explicit) ->
    [[[source(I), "_", K, ": batch_", n(I), ".", K, ",\n"] || #{index := I} <- Sources, K <- ["valid", "layout", "payload"]],
     [[link_name(I), "_eligible: ", eligibility(Explicit, D, maps:get(I, Spans), N), ",\n"]
        || #{index := I, destination_index := D, slots := N} <- Links],
     [[boundary(B), "_ready: io.", boundary(B), "_ready,\n"] || B <- Boundaries],
     [[K, ": io.", K, ",\n"] || {K, _} <- RemoteInputs]].

%% Host consumption follows receiver disposition, not reservation or publication acceptance.
-spec ingress_step(none | map(), [receiver_wiring()]) -> iodata().
ingress_step(none, _) -> [];
ingress_step(Ingress, Wiring) ->
    ["let ingress_step = ingress::tick(s.ingress, io.reset, startup_done, io.ingress_valid,\n",
     "ingress::decode(io.ingress_data), ", host_mask(Ingress, Wiring), ");\n"].

%% Only the committed receiver step can retire a selected capture or release its lease.
-spec retire([map()], #{non_neg_integer() => non_neg_integer()}) -> iodata().
retire(Links, Spans) ->
    [[link_name(I), "_take: or_reduce(step_", n(D), ".output.take[", n(maps:get(I, Spans)), "+:bits[", n(N), "]]),\n",
      link_name(I), "_release_valid: step_", n(D), ".output.release[", n(maps:get(I, Spans)), "+:bits[", n(N), "]],\n"]
     || #{index := I, destination_index := D, slots := N} <- Links].

%% Register each component's one chosen transition; no output observes these next-state fields.
-spec updates([map()], [map()], boolean(), boolean()) -> iodata().
updates(Sources, Arithmetic, Host, Explicit) ->
    [[[actor(I), ": step_", n(I), ".state,\n"] || #{index := I} <- Sources],
     optional(Host, "ingress: ingress_step,\n"), optional(Explicit, "activation: activation_step.state,\n"),
     xls_protocol_arithmetic:updates(Arithmetic)].

%% Inspection reads old machines; externally retained streams come from the transport preview.
-spec observations([map()], [map()], [clock_port()], boolean(), boolean(), boolean()) -> iodata().
observations(Sources, Boundaries, RemoteOutputs, Inspect, Explicit, Host) ->
    [optional(Inspect, ["inspect_value: match io.inspect_address {\n",
        [["u32:", n(I), " => inspection::observe_", n(I), "(s.", actor(I), ".owner.machine, s.", actor(I), ".started, io.reset),\n"] || #{index := I} <- Sources],
        "_ => bits[128]:0, },\n"]),
     "startup_done,\n",
     optional(Explicit, "start_ready: activation_step.output.start_ready, running: activation_step.output.running,\n"),
     optional(Host, "ingress_ready: ingress_offer.ready, ingress_fault: ingress_offer.fault,\n"),
     [[actor(I), "_failure: step_", n(I), ".output.owner.failure, ", actor(I), "_fault: preview.", source(I), "_fault,\n"] || #{index := I} <- Sources],
     [[boundary(B), "_", K, ": preview.", boundary(B), "_", K, ",\n"] || B <- Boundaries, K <- ["valid", "data"]],
     [[K, ": preview.", K, ",\n"] || {K, _} <- RemoteOutputs]].

%% Static facts expose the same interface before template or observation emission.
-spec static_descriptor(map(), [clock_port()], [clock_port()]) -> map().
static_descriptor(#{fabric := Fabric = #{sources := Sources, links := Links}, receivers := Receivers,
        ingress := Ingress, activation := Activation, arithmetic := Arithmetic, inspection := Inspection,
        bundle := #{topology := #{externals := Externals}}}, Inputs, Outputs) ->
    Crossings = maps:get(crossings, Fabric, []),
    Incoming = [I || #{index := I, direction := incoming} <- Crossings],
    Host = Ingress =/= none,
    Explicit = Activation =:= explicit_start,
    #{top=>protocol_network,clock_proc=>network_clock,actor_runtime=>true,eligible=>false,
        actors=>length(Sources),links=>length(Links),additional_state_bits=>(case Host of true->maps:get(state_bits,Ingress);false->0 end)+(case Explicit of true->1;false->0 end)+lists:sum([W||#{cursor_bits:=W}<-Arithmetic]),
        arithmetic=>Arithmetic,
        activation=>Activation,inspection=>Inspection,
        native_indices=>[I||#{index:=I}<-Sources],
        crossings=>[#{index=>I,direction=>D,source_index=>S,destination_index=>T,slots=>N,
            classes=>[maps:with([slot,codec],C)||C<-Cs]}
            ||#{index:=I,direction:=D,source_index:=S,destination_index:=T,slots:=N,classes:=Cs}<-Crossings],
        crossing_state_bits=>length(Incoming),
        ingress=>Ingress,
        capacity=>unestablished,network_progress=>unestablished,
        initialization=>source_init_and_declared_startup,publication=>atomic_old_outbox_batch,
        startup_messages=>lists:sum([N||#{manifest:=#{inbox:=#{startup:=#{count:=N}}}}<-Receivers]),
        startup_done=>all_declared_records_consumed_not_application_readiness,
        reset=>common_clock_cancels_all_ownership,
        inputs=>fields(Inputs),outputs=>fields(Outputs),
        externals=>[#{index=>I,id=>iolist_to_binary(io_lib:format("~0tp",[Id]))}||{I,#{id:=Id}}<-lists:enumerate(0,Externals)],
        boundaries=>[#{source_index=>I,output_index=>D,name=>list_to_binary(boundary(B)),external_index=>external_index(Id,Externals)}
            ||B=#{source_index:=I,output:=#{index:=D,destination:={external,Id}}}<-maps:get(boundaries,Fabric)]}.

%% Component identities name exactly the receiver and optional inputs used by this plan.
-spec component_files(map()) -> [string()].
component_files(#{fabric := Fabric, receivers := Receivers, ingress := Ingress, inspection := Inspection}) ->
    ["dslx/transport.x" | [binary_to_list(File) || #{file := File} <- Receivers]] ++
        xls_protocol_partition:files(Fabric) ++ optional(Ingress =/= none, ["dslx/ingress.x"]) ++
        optional(Inspection =:= process, ["network/process_observation.x"]).

%% Running is registered: start_valid cannot open captures on its handshake edge.
-spec eligibility(boolean(),non_neg_integer(),non_neg_integer(),pos_integer()) -> iodata().
eligibility(Explicit,Actor,Offset,Width) ->
    Mask=["eligible_",n(Actor),"[",n(Offset),"+:bits[",n(Width),"]]"],
    case Explicit of
        true->["activation::eligible(s.activation, io.reset, ",Mask,")"];
        false->Mask
    end.

%% These observations use old ownership/faults, never same-edge consume or ready.
%% Initialization/entry work and already published captures need not be drained.
-spec activation_step(boolean(),boolean(),[map()],[non_neg_integer()]) -> iodata().
activation_step(false,_,_,_) -> [];
activation_step(true,Host,Sources,Incoming) ->
    ["let activation_step = activation::tick(s.activation, activation::Conditions {\n",
     "reset: io.reset, startup_done, ingress_idle: ",case Host of true->"ingress_offer.ready";false->"true" end,
     ", ingress_valid: ",case Host of true->"io.ingress_valid";false->"false" end,",\n",
     "fault: ",optional(Host,"ingress_offer.fault || "),
     [["preview.",xls_protocol_partition:name(I),"_fault || "]||I<-Incoming],
     lists:join(" || ",[["step_",n(I),".output.owner.failure != u16:0 || preview.",source(I),"_fault"]||#{index:=I}<-Sources]),
     " }, io.start_valid);\n"].

%% Each receiver imports exactly its own capture links and optional host/grant inputs.
-spec receiver(receiver_wiring(), [map()]) -> iodata().
receiver(#{index := I, links := Links, host_slot := Host}, Arithmetic) ->
    ["let step_", n(I), " = ", actor(I), "::local_inbox_batch_tick(s.", actor(I), ", ", actor(I), "::LocalInboxInputs {\n",
     "reset: io.reset, output_ready: preview.", source(I), "_ready,\n", xls_protocol_arithmetic:inputs(I, Arithmetic),
     optional(Host =/= none, ["host_valid: ingress_offer.valid[", n(I), "+:u1], host_frame: ingress_offer.frame,\n"]),
     [[link_name(K), "_", Field, ": preview.", link_name(K), "_", Field, ",\n"]
        || #{index := K} <- Links, Field <- ["selected", "available", "payloads"]], "});\n"].

%% Host masks retain full-topology indices even when this role has holes.
-spec host_mask(map(), [receiver_wiring()]) -> iodata().
host_mask(#{actors:=N},Receivers) ->
    ByIndex=maps:from_list([{I,R}||R=#{index:=I}<-Receivers]),
    lists:join(" ++ ",[host_take(maps:get(I,ByIndex,#{}))||I<-lists:seq(N-1,0,-1)]).

%% Host retirement is a source disposition, not initial inbox reservation.
-spec host_take(map()) -> iodata().
host_take(#{index := I, host_slot := At}) when At =/= none ->
    ["step_",n(I),".output.take[",n(At),"+:u1]"];
host_take(_) -> "u1:0".

%% Omitted interfaces introduce no state or unused pins.
-spec optional(boolean(),list()) -> list().
optional(true,Value) -> Value;
optional(false,_) -> [].

%% Packed field order is shared by the DSLX record, pin adapter and JSON consumer.
-spec structure(string(),[{string(),pos_integer()}]) -> iodata().
structure(Name,Fields) -> ["// Sampled network clock interface.\npub struct ",Name," {\n",
    [[K,": bits[",n(W),"],\n"]||{K,W}<-Fields],"}\n"].

%% JSON retains the same exact widths rather than inferring them from generated text.
-spec fields([{string(),pos_integer()}]) -> [map()].
fields(Fields) -> [#{name=>list_to_binary(K),width=>W}||{K,W}<-Fields].

%% Names follow deterministic elaborated instance and recipient identities.
-spec actor(non_neg_integer()) -> string().
actor(I) -> "actor_"++n(I).
%% Publisher identities agree with the existing transport port manifest.
-spec source(non_neg_integer()) -> string().
source(I) -> "source_"++n(I).
%% Avoid the Erlang link BIF name for physical pair identifiers.
-spec link_name(non_neg_integer()) -> string().
link_name(I) -> "link_"++n(I).
%% External destinations stay separate streams; there is no implicit merger.
-spec boundary(map()) -> string().
boundary(#{source_index:=I,output:=#{index:=D}}) -> "boundary_"++n(I)++"_"++n(D).
%% Only checked elaboration integers enter generated identifiers and slices.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).

%% Canonical normalized topology order is shared by the boundary and host binding.
-spec external_index(atom() | non_neg_integer() | tuple(),[map()]) -> non_neg_integer().
external_index(Id,Externals) ->
    [Index]=[I||{I,#{id:=Name}}<-lists:enumerate(0,Externals),Name=:=Id],Index.
