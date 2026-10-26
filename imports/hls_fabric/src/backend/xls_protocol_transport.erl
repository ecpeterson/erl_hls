-module(xls_protocol_transport).
-moduledoc "Plans source-bound transport wiring and renders its fixed publication/capture algorithms. Named observe, select and commit expressions retain dependency structure until DSLX emission.".
-export([plan/1, descriptor/1, emit/1]).
-export_type([plan/0, descriptor/0]).

%% Match arms share equal projections, while every source instance keeps independent state.
-type projection_group() :: #{selectors := [{non_neg_integer(), non_neg_integer()}],
    bits := [hls_protocol_projection:bit()], slot := non_neg_integer()}.
%% A shared source shape contains only the fields that affect its generated behavior.
-type source_shape() :: #{payload_width := pos_integer(), destinations := pos_integer(),
    sequence_slots := pos_integer(), output_width := pos_integer(),
    masks := [#{layout := non_neg_integer(), mask := non_neg_integer()}],
    outputs := [#{index := non_neg_integer(), width := pos_integer(), groups := [projection_group()]}]}.
%% One shared shape has a stable generated type/function identifier.
-record(source_definition, {index :: non_neg_integer(), shape :: source_shape()}).
%% An instance binds an unchanged checked source to one shared shape definition.
-record(source_instance, {source :: hls_protocol_source:source(), shape :: non_neg_integer()}).
%% Interface field order is also packed DSLX/pin order.
-type clock_port() :: {string(), pos_integer()}.
%% Commit and output constructors preserve this order; expressions remain structured values.
-type fields() :: [{string(), xls_dslx:expr()}].

-doc "Read-only transport program: observations read held state; selection sees those observations; crossing checks precede capture; each component commits once. Outputs use pre-edge observations, never next state. These facts do not establish fairness or progress.".
-type descriptor() :: #{inputs := [clock_port()], outputs := [clock_port()],
    observe := [xls_dslx:binding()], select := [xls_dslx:binding()],
    crossing := [xls_dslx:binding()], commit := fields(), observations := fields()}.
%% Topology is retained for codec emission; normalized definitions and wiring own rendering.
-record(plan, {fabric :: hls_protocol_fabric:plan(),
    definitions :: [#source_definition{}],
    sources :: [#source_instance{}], links :: [hls_protocol_fabric:link()],
    crossing :: xls_protocol_partition:wiring(), transition :: descriptor()}).

-doc "An unchanged in-process transport wiring plan. Creating it resolves shapes, projection groups, ports and all transition expressions without reading templates or emitting source.".
-opaque plan() :: #plan{}.

-doc "Normalizes a checked fabric into named publication, capture and crossing transitions. Missing or ambiguous delivery endpoints fail during planning; source, capacity and placement validation belong to the fabric owner.".
-spec plan(hls_protocol_fabric:plan()) -> plan().
plan(Fabric = #{sources := Sources, links := Links}) ->
    Keys = lists:usort([source_shape(S) || S <- Sources]),
    Definitions = [#source_definition{index = I, shape = K} || {I, K} <- lists:enumerate(0, Keys)],
    Ids = maps:from_list([{K, I} || {I, K} <- lists:enumerate(0, Keys)]),
    Instances = [#source_instance{source = S, shape = maps:get(source_shape(S), Ids)} || S <- Sources],
    Crossing = xls_protocol_partition:wiring(Fabric),
    #plan{fabric = Fabric, definitions = Definitions, sources = Instances, links = shapes(Links),
        crossing = Crossing, transition = transition(Fabric, Instances, Crossing)}.

-doc "Returns the exact retained transition consumed by emission, with structured expressions and ordered phases. Treat it as read-only; this is not a serialized plan input.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{transition = Transition}) -> Transition.

-doc "Returns DSLX, pin adapter, port manifest and crossing codecs without writing output. Requires an unchanged plan. The sampled clock uses one stage with no boundary flops; recipient readiness is input data and cannot stall the proc. Template reads occur here; no capacity or progress admission is granted.".
-spec emit(plan()) -> hls_generated_files:output().
emit(#plan{fabric = Fabric = #{links := Links}, definitions = Definitions, sources = Sources,
        links = Shapes, crossing = Crossing, transition = T = #{inputs := Inputs, outputs := Outputs}}) ->
    Source = ["import protocol_transport as p;\nimport axis;\nconst_assert!(axis::FRAME_BITS == u32:128);\n",
        maps:get(imports, Crossing), structure("Inputs", Inputs), structure("Outputs", Outputs),
        [source(S) || S <- Definitions], [link_shape(L) || L <- Shapes],
        "pub struct State {\n", [[sname(I), ": S", n(Shape), ",\n"] || #source_instance{source = #{index := I}, shape = Shape} <- Sources],
        [[lname(I), ": L", n(Shape), ",\n"] || #{index := I, shape := Shape} <- Links],
        maps:get(state, Crossing), "}\n", tick(T), template("protocol_clock.x.in", [])],
    Files = hls_generated_files:merge([xls_protocol_partition:emit(Fabric),
        #{"transport.x" => Source,
          "protocol_fabric.sv" => sv_protocol_ports:emit(Inputs, Outputs, "protocol_fabric", "protocol_fabric_core"),
          "ports.json" => json:encode(#{inputs => [#{name => list_to_binary(K), width => W} || {K, W} <- Inputs],
              outputs => [#{name => list_to_binary(K), width => W} || {K, W} <- Outputs]})}]),
    #{files => Files, result => ok}.

%% Width-identical links share declarations, but never state instances.
-spec shapes([hls_protocol_fabric:link()]) -> [hls_protocol_fabric:link()].
shapes(Links) -> [L || {_, L} <- lists:sort(maps:to_list(maps:from_list([{maps:get(shape, L), L} || L <- Links])))].

%% Only payload wiring, masks and dimensions define shape equality.
-spec source_shape(hls_protocol_source:source()) -> source_shape().
source_shape(S = #{outputs := Outputs}) ->
    (maps:with([payload_width, destinations, sequence_slots, output_width, masks], S))#{outputs => [
        (maps:with([index, width], O))#{groups => projection_groups(Rows)} || O = #{rows := Rows} <- Outputs]}.

%% Port order is the DSLX struct bit order and the adapter's concatenation order.
-spec ports(hls_protocol_fabric:plan()) -> {[clock_port()], [clock_port()]}.
ports(Plan=#{sources:=Sources,links:=Links,boundaries:=Boundaries}) ->
    {RemoteInputs,RemoteOutputs}=xls_protocol_partition:ports(Plan),
    Inputs=[{"reset",1}]++lists:append([[{sname(I)++"_valid",1},{sname(I)++"_layout",8},
        {sname(I)++"_payload",W}]||#{index:=I,payload_width:=W}<-Sources])++
        lists:append([[{lname(I)++"_take",1},{lname(I)++"_eligible",N},
            {lname(I)++"_release_valid",N}]||#{index:=I,slots:=N}<-Links])++
        [{bname(I,D)++"_ready",1}||#{source_index:=I,output:=#{index:=D}}<-Boundaries],
    Outputs=lists:append([[{sname(I)++"_ready",1},{sname(I)++"_fault",1}]||#{index:=I}<-Sources])++
        lists:append([[{lname(I)++"_capture",1},{lname(I)++"_capture_slot",8},
            {lname(I)++"_selected",N},{lname(I)++"_available",N},{lname(I)++"_leased",N},
            {lname(I)++"_payloads",W}]||#{index:=I,slots:=N,payload_bits:=W}<-Links])++
        lists:append([[{bname(I,D)++"_valid",1},{bname(I,D)++"_data",W}]
            ||#{source_index:=I,output:=#{index:=D,width:=W}}<-Boundaries]),
    {Inputs++RemoteInputs,Outputs++RemoteOutputs}.

%% Fixed publication semantics live in DSLX; only concrete projection arms and widths vary.
-spec source(#source_definition{}) -> iodata().
source(#source_definition{index = I, shape = #{payload_width := W, destinations := D, sequence_slots := N,
        outputs := Outputs, output_width := Total, masks := Masks}}) ->
    template("protocol_transport_source.x.in",
        aliases(["STATE_DECL", "VIEW_STATE", "NEXT_STATE", "NEXT_RESULT", "NEXT_CONSTRUCTOR"], ["S", n(I)]) ++
        aliases(["VIEW_RESULT", "VIEW_CONSTRUCTOR"], ["V", n(I)]) ++
        aliases(["MASK_FUNCTION", "VIEW_MASK", "NEXT_MASK"], ["mask_", n(I)]) ++
        aliases(["MASK_TYPE_BITS", "EMPTY_MASK_BITS"], n(D*N)) ++
        aliases(["VIEW_PAYLOAD_BITS", "LAYOUT_OFFSET", "INPUT_PAYLOAD_BITS"], n(W)) ++
        aliases(["PUBLICATION_DESTINATIONS", "READY_BITS"], n(D)) ++ [
        {"VIEW_FUNCTION", ["view_", n(I)]}, {"NEXT_FUNCTION", ["next_", n(I)]},
        {"SNAPSHOT_BITS", n(W+8)}, {"SEQUENCE_SLOTS", n(N)},
        {"VIEW", structure("V"++n(I), [{"ready",1},{"fault",1},{"valid",D},{"data",Total},{"channel",D*8}])},
        {"MASK_ARMS", [["u8:",n(L)," => (true, ",bits(D*N),":",n(M),"),\n"] || #{layout := L, mask := M} <- Masks]},
        {"PROJECTIONS", [["let (data_",n(K),", class_",n(K),") = match (layout, indices[u32:",n(K),"]) {\n",
            projection_rows(Groups, Width), "_ => (",bits(Width),":0, u8:0), };\n"]
            || #{index := K, width := Width, groups := Groups} <- Outputs]},
        {"DATA", concat(["data_"++n(K) || #{index := K} <- lists:reverse(Outputs)], bits(Total)++":0")},
        {"CHANNEL", concat(["class_"++n(K) || #{index := K} <- lists:reverse(Outputs)], bits(D*8)++":0")}]).

%% Heterogeneous payload slots keep named fields and the original packed field order.
-spec link_shape(hls_protocol_fabric:link()) -> iodata().
link_shape(#{shape := Shape, widths := Widths, slots := N, payload_bits := Total, input_bits := Max}) ->
    Rows = lists:enumerate(0, Widths),
    template("protocol_transport_link.x.in",
        aliases(["STATE_DECL", "VIEW_STATE", "NEXT_STATE", "NEXT_RESULT", "NEXT_CONSTRUCTOR"], ["L", n(Shape)]) ++
        aliases(["VIEW_RESULT", "VIEW_CONSTRUCTOR", "NEXT_VIEW"], ["LV", n(Shape)]) ++
        aliases(["ORDER_SLOTS", "ELIGIBLE_BITS", "RELEASE_BITS"], n(N)) ++ [
        {"VIEW_FUNCTION", ["link_view_", n(Shape)]}, {"NEXT_FUNCTION", ["link_next_", n(Shape)]},
        {"INPUT_BITS", n(Max)},
        {"CAPTURES", [["capture_",n(K),": p::Capture<",n(W),">,\n"] || {K,W} <- Rows]},
        {"VIEW", structure("LV"++n(Shape), [{"ready",1},{"selected",N},{"available",N},{"leased",N},{"payloads",Total}])},
        {"READY", lists:join(" || ", [["(slot == u8:",n(K)," && s.capture_",n(K),".owner == u2:0)"] || {K,_} <- Rows])},
        {"AVAILABLE", concat([["(!reset && s.capture_",n(K),".owner == u2:1)"] || {K,_} <- lists:reverse(Rows)], "false")},
        {"LEASED", concat([["(!reset && s.capture_",n(K),".owner == u2:2)"] || {K,_} <- lists:reverse(Rows)], "false")},
        {"PAYLOADS", concat([["s.capture_",n(K),".payload"] || {K,_} <- lists:reverse(Rows)], "false")},
        {"ARRIVALS", [["let arrive_",n(K)," = valid && view.ready && slot == u8:",n(K),";\n"] || {K,_} <- Rows]},
        {"CAPTURE_UPDATES", [["capture_",n(K),": p::capture_next(s.capture_",n(K),", reset, arrive_",n(K),
            ", payload as ",bits(W),", ",bit("view.selected",K)," && take, ",bit("release",K),"),\n"] || {K,W} <- Rows]},
        {"ARRIVAL_MASK", concat(["arrive_"++n(K) || {K,_} <- lists:reverse(Rows)], "false")}]).

%% Resolve every dependency once; observers cannot reference the commit constructor.
-spec transition(hls_protocol_fabric:plan(), [#source_instance{}], xls_protocol_partition:wiring()) -> descriptor().
transition(Fabric = #{sources := Sources, links := Links, boundaries := Boundaries}, Instances, Crossing) ->
    {Inputs, Outputs} = ports(Fabric),
    Observe = [xls_dslx:bind(sname(I), xls_dslx:call("view_"++n(Shape),
        [state(sname(I)), io("reset"), io(sname(I)++"_layout")])) || #source_instance{source = #{index := I}, shape = Shape} <- Instances],
    Select = lists:append([[xls_dslx:bind(lname(I)++"_slot", link_slot(L)),
        xls_dslx:bind(lname(I), xls_dslx:call("link_view_"++n(Shape),
            [state(lname(I)), io("reset"), io(lname(I)++"_eligible"), ref(lname(I)++"_slot")]))]
        || L = #{index := I, shape := Shape} <- Links]),
    SourceNext = [{sname(I), xls_dslx:call("next_"++n(Shape), [state(sname(I)), io("reset"),
        io(sname(I)++"_valid"), io(sname(I)++"_layout"), io(sname(I)++"_payload"),
        concatenate([ready(I, O, Links++maps:get(crossings, Fabric, [])) || O <- lists:reverse(Os)], D)])}
        || #source_instance{source = #{index := I, destinations := D, outputs := Os}, shape = Shape} <- Instances],
    LinkNext = [{lname(I), xls_dslx:call("link_next_"++n(Shape), [state(lname(I)), io("reset"),
        link_valid(L), ref(lname(I)++"_slot"), link_payload(L), io(lname(I)++"_take"),
        io(lname(I)++"_release_valid"), ref(lname(I))])} || L = #{index := I, shape := Shape} <- Links],
    Values = maps:from_list(lists:append([[{sname(I)++"_"++K, field(sname(I), K)} || K <- ["ready","fault"]]
        || #{index := I} <- Sources]) ++ lists:append([
        [{lname(I)++"_capture", xls_dslx:binary('&&', link_valid(L), field(lname(I), "ready"))},
         {lname(I)++"_capture_slot", ref(lname(I)++"_slot")}] ++
        [{lname(I)++"_"++K, field(lname(I), K)} || K <- ["selected","available","leased","payloads"]]
        || L = #{index := I} <- Links]) ++ lists:append([
        [{bname(I,D)++"_valid", xls_dslx:slice(field(sname(I), "valid"), D, 1)},
         {bname(I,D)++"_data", xls_dslx:slice(field(sname(I), "data"), At, W)}]
        || #{source_index := I, output := #{index := D, offset := At, width := W}} <- Boundaries]) ++ maps:get(values, Crossing)),
    #{inputs => Inputs, outputs => Outputs, observe => Observe, select => Select,
        crossing => maps:get(views, Crossing), commit => SourceNext++LinkNext++maps:get(next, Crossing),
        observations => [{Name, maps:get(Name, Values)} || {Name,_} <- Outputs]}.

%% The renderer cannot reorder phases or recompute routing from the source graph.
-spec tick(descriptor()) -> iodata().
tick(#{observe := Observe, select := Select, crossing := Crossing, commit := Commit, observations := Outputs}) ->
    Body = xls_dslx:block(Observe++Select++Crossing, xls_dslx:construct("Tick", [
        {"state", xls_dslx:construct("State", Commit)}, {"output", xls_dslx:construct("Outputs", Outputs)}])),
    ["// Pre-edge observations and one commit per component.\n",
     "pub struct Tick { state: State, output: Outputs }\n",
     "pub fn tick(s: State, io: Inputs) -> Tick ", xls_dslx:render(Body), "\n"].

%% A native recipient uses held slot ownership; a crossing uses sampled peer credit.
-spec ready(non_neg_integer(), hls_protocol_source:output(), [hls_protocol_fabric:link()]) -> xls_dslx:expr().
ready(I, #{index := D, destination := {external,_}}, _) -> io(bname(I,D)++"_ready");
ready(I, #{index := D}, Links) ->
    [Link] = lists:usort([L || L = #{source_index := S, output_index := O} <- Links, S =:= I, O =:= D]),
    case Link of
        #{index := K, direction := outgoing} -> io(xls_protocol_partition:name(K)++"_ready");
        #{index := K} -> field(lname(K), "ready")
    end.

%% Incoming ports replace only the absent source's class selector.
-spec link_slot(hls_protocol_fabric:link()) -> xls_dslx:expr().
link_slot(#{index := I, direction := incoming}) -> io(xls_protocol_partition:name(I)++"_slot");
link_slot(#{source_index := S, output_index := D}) -> xls_dslx:slice(field(sname(S), "channel"), D*8, 8).

%% Canonical validation gates capture before any compact payload is stored.
-spec link_valid(hls_protocol_fabric:link()) -> xls_dslx:expr().
link_valid(#{index := I, direction := incoming}) -> field(xls_protocol_partition:name(I), "capture");
link_valid(#{source_index := S, output_index := D}) -> xls_dslx:slice(field(sname(S), "valid"), D, 1).

%% Payload wires come from the held publication or the checked boundary projection.
-spec link_payload(hls_protocol_fabric:link()) -> xls_dslx:expr().
link_payload(#{index := I, direction := incoming}) -> ref(xls_protocol_partition:name(I)++"_payload");
link_payload(#{source_index := S, output := #{offset := At, width := W}}) -> xls_dslx:slice(field(sname(S), "data"), At, W).

%% Empty publications retain the planner's harmless physical placeholder.
-spec concatenate([xls_dslx:expr()], pos_integer()) -> xls_dslx:expr().
concatenate([], Width) -> xls_dslx:literal({bits, Width}, 0);
concatenate([One], _) -> One;
concatenate([First|Rest], Width) -> xls_dslx:binary('++', First, concatenate(Rest, Width)).

%% Local variable, input and held-state references remain distinct expression nodes.
-spec ref(string()) -> xls_dslx:expr().
ref(Name) -> xls_dslx:ref(Name).
%% Select a named field on a local observation.
-spec field(string(), string()) -> xls_dslx:expr().
field(Name, Field) -> xls_dslx:field(ref(Name), Field).
%% Inputs are sampled for the current edge.
-spec io(string()) -> xls_dslx:expr().
io(Name) -> field("io", Name).
%% All component observations originate in pre-edge state.
-spec state(string()) -> xls_dslx:expr().
state(Name) -> field("s", Name).

%% Templates contain fixed algorithms; bindings are elaborated dimensions or heterogeneous wiring.
-spec template(string(), [{string(), iodata()}]) -> binary().
template(Name, Bindings) ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_fabric), "xls", "templates", Name])),
    xls_template:render(Bytes, [{list_to_binary("@@"++Key++"@@"), Value} || {Key,Value} <- Bindings]).

%% These bits reference the retained ordinary payload, with numeric low-bit-first planning.
-spec expression([hls_protocol_projection:bit()]) -> iolist().
expression(Bits) -> xls_protocol_bits:expression("payload", Bits).

%% Static packed records keep ABI ordering visible in generated DSLX.
-spec structure(string(),[{string(),pos_integer()}]) -> iolist().
structure(Name,Fields) -> ["pub struct ",Name," {",[[K,": ",bits(W),",\n"]||{K,W}<-Fields],"}\n"].
%% Empty recipients still use the planner's harmless one-bit physical placeholder.
-spec concat([iodata()],iodata()) -> iolist().
concat([],Default) -> [Default];
concat(Parts,_) -> ["(",lists:join(" ++ ",Parts),")"].
%% A one-bit projection is a boolean in DSLX.
-spec bit(string(),non_neg_integer()) -> iolist().
bit(Value,J) -> [Value,"[",n(J),"+:u1]"].
%% All dimensions are known at elaboration.
-spec bits(pos_integer()) -> string().
bits(N) -> "bits["++n(N)++"]".
%% Actor identities come from deterministic topology enumeration.
-spec sname(non_neg_integer()) -> string().
sname(I) -> "source_"++n(I).
%% Each logical sender/destination pair owns separate state.
-spec lname(non_neg_integer()) -> string().
lname(I) -> "link_"++n(I).
%% Boundary identity includes both logical source and recipient.
-spec bname(non_neg_integer(),non_neg_integer()) -> string().
bname(I,D) -> "boundary_"++n(I)++"_"++n(D).
%% Only elaborated integers enter DSLX identifiers or literals.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).

%% Equal projections share a match arm without merging logical source instances.
-spec projection_groups([hls_protocol_source:row()]) -> [projection_group()].
projection_groups(Rows) ->
    Selectors = [{L, S} || #{layout := L, sequence := S} <- Rows],
    true = length(Selectors) =:= length(lists:usort(Selectors)),
    Groups = lists:foldl(fun(#{layout := L, sequence := S, bits := Bits, capture_slot := C}, Acc) ->
        maps:update_with({Bits, C}, fun(Keys) -> [{L, S} | Keys] end, [{L, S}], Acc)
    end, #{}, Rows),
    [#{selectors => lists:sort(Keys), bits => Bits, slot => C}
        || {{Bits, C}, Keys} <- lists:sort(maps:to_list(Groups))].

%% The renderer consumes the selected alternatives, never rediscovers their grouping.
-spec projection_rows([projection_group()], pos_integer()) -> iodata().
projection_rows(Groups, Width) ->
    [[lists:join(" | ", [["(u8:", n(L), ", u8:", n(S), ")"] || {L, S} <- Keys]),
        " => (", expression(Bits ++ lists:duplicate(Width-length(Bits), 0)),
        ", u8:", n(C), "),\n"] || #{selectors := Keys, bits := Bits, slot := C} <- Groups].

%% Name every distinct template position while sharing its checked concrete value.
-spec aliases([string()], iodata()) -> [{string(), iodata()}].
aliases(Names, Value) -> [{Name, Value} || Name <- Names].
