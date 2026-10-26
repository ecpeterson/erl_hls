-module(xls_protocol_bridge).
-moduledoc "Elaborates static partition pins around the shared typed DSLX bridge and unchanged source boundary.".
-export([emit/3]).
-export_type([manifest/0]).

-doc "The emitted bridge's packed ports, compact crossing codecs, raw-boundary manifest and required hardware/support hashes. The attachment identity is lowercase hex here; the host bridge descriptor retains its raw bytes.".
-type manifest() :: #{frame_layout := hls_frame_layout:layout(), host := 1 .. ((1 bsl 16) - 1), service := 1 .. ((1 bsl 16) - 1), control := rectangle,
    control_adapter := hls_protocol_control:hardware(), native_indices := [non_neg_integer()],
    actors := non_neg_integer(), externals := [xls_protocol_boundary:group()], eligible := false,
    libraries := [xls_protocol_network:component()], top := protocol_bridge_top,
    links := [xls_protocol_network:crossing()], identity := binary(), bridge_state_bits := non_neg_integer(),
    boundary := hls_protocol_boundary:manifest(), reset := retire_deployment_transports_then_coordinated_reset,
    ordering := per_logical_sender_destination, inputs := [xls_protocol_network:packed_port()],
    outputs := [xls_protocol_network:packed_port()], dslx_sha256 := binary(),
    components := [xls_protocol_network:component()]}.

%% Mechanical adapter fields retain the same order and widths as their DSLX declarations.
-type clock_port() :: {string(), pos_integer()}.

-doc "Returns in-memory sampled-clock bridge files without writing output. UpstreamFiles supplies root-relative boundary bytes for exact component hashes. Static link/class identities come from hls_protocol_bridge; old boundary observations supply credit and retained offers, and only the final call applies accepted transfers. Adds bounded framing and reservation state, no replicated native payloads. Output fault includes any native actor/transport failure; retirement masks both directions until coordinated reset. Returns exact emitted-input hashes and state accounting with eligibility false.".
-spec emit(hls_protocol_bridge:bridge(), hls_protocol_boundary:manifest(),
    hls_generated_files:files()) -> hls_generated_files:output(manifest()).
emit(Bridge=#{identity:=Identity,incoming:=Incoming,outgoing:=Outgoing,credits:=Credits},
        Boundary,UpstreamFiles) ->
    I=length(Incoming),C=length(Credits),O=length(Outgoing),
    Inputs=[{"reset",1},{"retire",1},{"s_app_tdata",32},{"s_app_tlast",1},{"s_app_tvalid",1},{"m_app_tready",1}],
    Outputs=[{"s_app_tready",1},{"m_app_tdata",32},{"m_app_tlast",1},{"m_app_tvalid",1},{"fault",1},{"running",1}],
    Source = source(Bridge, Boundary, Inputs, Outputs),
    GeneratedFiles=#{"bridge/bridge.x"=>Source,
        "bridge/protocol_bridge_top.sv"=>sv_protocol_ports:emit(Inputs,Outputs,"protocol_bridge_top","protocol_bridge_core")},
    ComponentFiles=hls_generated_files:merge([UpstreamFiles,GeneratedFiles]),
    %% RX=360, TX=310; attachment/fault=67, event sequence/cursor=48.
    StateBits=785+32*I+C+42*O,
    Manifest=(maps:without([identity,incoming,outgoing,credits,links],Bridge))#{top=>protocol_bridge_top,
      links=>[#{index=>N,direction=>D,source_index=>S,destination_index=>T,slots=>Slots,
        classes=>[maps:with([slot,codec],Cl)||Cl<-Cs]}
        ||#{index:=N,direction:=D,source_index:=S,destination_index:=T,slots:=Slots,classes:=Cs}<-maps:get(links,Bridge)],
      identity=>binary:encode_hex(Identity,lowercase),bridge_state_bits=>StateBits,boundary=>Boundary,
      reset=>retire_deployment_transports_then_coordinated_reset,ordering=>per_logical_sender_destination,
      inputs=>[#{name=>list_to_binary(N),width=>W}||{N,W}<-Inputs],
      outputs=>[#{name=>list_to_binary(N),width=>W}||{N,W}<-Outputs],
      dslx_sha256=>hls_generated_files:hash(Source),
      components=>[#{file=>list_to_binary(F),sha256=>hls_generated_files:hash(maps:get(F,ComponentFiles))}
        ||F<-["boundary/boundary.x","bridge/protocol_bridge_top.sv"]]},
    Files=hls_generated_files:merge([GeneratedFiles,#{"bridge/manifest.json"=>json:encode(Manifest)}]),
    #{files=>Files,result=>Manifest}.

%% The template makes the old-observation/framing/final-acceptance order explicit.
-spec source(hls_protocol_bridge:bridge(), hls_protocol_boundary:manifest(), [clock_port()], [clock_port()]) -> iodata().
source(#{identity := Identity, host := Host, service := Service,
        incoming := Incoming, outgoing := Outgoing, credits := Credits,
        control_adapter := #{bridge_decoder := Decoder}},
        #{outputs := NativeOutputs, externals := Externals}, Inputs, Outputs) ->
    I = length(Incoming), C = length(Credits), O = length(Outgoing), E = length(Externals),
    Directory = filename:join(code:priv_dir(hls_fabric), "xls/templates"),
    {ok, Template} = file:read_file(filename:join(Directory, "protocol_bridge.x.in")),
    {ok, Clock} = file:read_file(filename:join(Directory, "protocol_boundary_clock.x.in")),
    Bindings = [
        {<<"@@CONTROL_DECODER@@">>, Decoder},
        {<<"@@INPUT_FIELDS@@">>, fields(Inputs)},
        {<<"@@OUTPUT_FIELDS@@">>, fields(Outputs)},
        {<<"@@STATE_DIMENSIONS@@">>, dimensions([I, C, O])},
        {<<"@@INPUT_DIMENSIONS@@">>, dimensions([I, C, O, E])},
        {<<"@@SAMPLE_FIELDS@@">>, [[remote(Link), "_slot: packet.slot, ",
            remote(Link), "_frame: packet.frame as bits[axis::FRAME_BITS],\n"] || Link <- Incoming]},
        {<<"@@CHILD_FAULT@@">>, child_fault(NativeOutputs)},
        {<<"@@INCOMING_LINKS@@">>, link_indices(Incoming)},
        {<<"@@INCOMING_READY@@">>, lists:join(",", [["old.", remote(Link), "_ready"]
            || Link <- Incoming])},
        {<<"@@CREDITS@@">>, credits(Credits)},
        {<<"@@OUTGOING_LINKS@@">>, link_indices(Outgoing)},
        {<<"@@OUTGOING_OFFERS@@">>, lists:join(",", [offer(remote(Link), "slot", "frame")
            || Link <- Outgoing])},
        {<<"@@EXTERNAL_OFFERS@@">>, lists:join(",", [offer("external_" ++ n(N), "zero", "data")
            || #{index := N} <- Externals])},
        {<<"@@IDENTITY@@">>, n(binary:decode_unsigned(Identity, little))},
        {<<"@@HOST@@">>, n(Host)},
        {<<"@@SERVICE@@">>, n(Service)},
        {<<"@@NETWORK_INPUTS@@">>, network_inputs(Incoming, Outgoing, Externals)}
    ],
    [xls_template:render(Template, Bindings),
        binary:replace(Clock, <<"boundary_clock">>, <<"bridge_clock">>, [global])].

%% Fault widths remain those of the child network's exact output interface.
-spec child_fault([xls_protocol_network:packed_port()]) -> iodata().
child_fault(Outputs) ->
    lists:join(" || ", [["old.", Name, " != bits[", n(Width), "]:0"]
        || #{name := Name, width := Width} <- Outputs,
           lists:suffix("_fault", binary_to_list(Name)) orelse
               lists:suffix("_failure", binary_to_list(Name))]).

%% Framing tables use original global link identities in the planner's order.
-spec link_indices([hls_protocol_partition:crossing()]) -> iodata().
link_indices(Links) -> lists:join(",", [["u16:", n(Index)] || #{index := Index} <- Links]).

%% A class credit samples its exact old capture-slot ownership bit.
-spec credits([hls_protocol_bridge:credit()]) -> iodata().
credits(Credits) ->
    lists:join(",", [["b::Credit { link:u16:", n(Link), ",slot:u8:", n(Slot),
        ",free:old.remote_", n(Link), "_free[", n(Slot), "+:u1] }"]
        || #{link := Link, slot := Slot} <- Credits]).

%% Bridge-local array ordinals differ from original global link identifiers.
-spec network_inputs([hls_protocol_partition:crossing()], [hls_protocol_partition:crossing()],
    [xls_protocol_boundary:group()]) -> iodata().
network_inputs(Incoming, Outgoing, Externals) ->
    [[[remote(Link), "_valid:step.output.incoming_valid[", n(Ordinal), "],\n"]
        || {Ordinal, Link} <- lists:enumerate(0, Incoming)],
     [[remote(Link), "_ready:step.output.outgoing_ready[", n(Ordinal), "],\n"]
        || {Ordinal, Link} <- lists:enumerate(0, Outgoing)],
     [["external_", n(Index), "_ready:step.output.external_ready[", n(Index), "],\n"]
        || #{index := Index} <- Externals]].

%% DSLX parameter order follows the typed bridge state and input declarations.
-spec dimensions([non_neg_integer()]) -> iodata().
dimensions(Values) -> lists:join(",", [n(Value) || Value <- Values]).

%% Static retained offers preserve the ordinary low-header frame ABI.
-spec offer(string(),string(),string()) -> iodata().
offer(P,Slot,Frame) ->
    ["b::Offer {valid:old.",P,"_valid,slot:",case Slot of "zero"->"u8:0";_->["old.",P,"_",Slot] end,
      ",frame:old.",P,"_",Frame," as bits[128]}"].
%% Only original global link indices determine raw crossing names.
-spec remote(hls_protocol_partition:crossing()) -> string().
remote(#{index:=I}) -> xls_protocol_partition:name(I).
%% Named pins retain their exact ordered widths in the mechanical adapter.
-spec fields([clock_port()]) -> iodata().
fields(Fields) -> [[Name, ":bits[", n(Width), "],\n"] || {Name, Width} <- Fields].
%% Only checked dimensions and indices enter generated text.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
