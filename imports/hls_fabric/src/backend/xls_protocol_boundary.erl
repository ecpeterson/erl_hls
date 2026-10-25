-module(xls_protocol_boundary).
-moduledoc "Wires declared external endpoints to static DSLX arbiters around the source-network transition.".
-export([plan/1, descriptor/1, emit/2]).
-export_type([plan/0]).

%% Pass-through ports and external groups fix the boundary before any hardware is rendered.
-record(plan, {descriptor :: map(), pass_inputs :: [map()], pass_outputs :: [map()]}).

-doc "An unchanged in-process boundary composition from plan/1. Retains the packed interface, external groups and pass-through ports independently of rendered bytes. It is not a serialized input format or hardware admission.".
-opaque plan() :: #plan{}.

-doc "Plans endpoint arbitration from a static network descriptor and checked external groups. Replaces individual producer ports with endpoint streams while retaining their declared order and arbitration-state accounting. Requires hls_protocol_boundary's checked groups; reads no templates and emits no hardware.".
-spec plan(map()) -> plan().
plan(#{network:=Network=#{inputs:=NetworkInputs,outputs:=NetworkOutputs,boundaries:=Boundaries},externals:=Groups}) ->
    BoundaryNames=lists:append([[<<Name/binary,"_ready">>,<<Name/binary,"_valid">>,<<Name/binary,"_data">>]||#{name:=Name}<-Boundaries]),
    PassInputs=[P||P=#{name:=Name}<-NetworkInputs,not lists:member(Name,BoundaryNames)],
    PassOutputs=[P||P=#{name:=Name}<-NetworkOutputs,not lists:member(Name,BoundaryNames)],
    Inputs=PassInputs++[#{name=>list_to_binary(external(I)++"_ready"),width=>1}||#{index:=I}<-Groups],
    Outputs=PassOutputs++lists:append([[#{name=>list_to_binary(external(I)++"_valid"),width=>1},
        #{name=>list_to_binary(external(I)++"_data"),width=>128}]||#{index:=I}<-Groups]),
    Bits=lists:sum([N||#{state_bits:=N}<-Groups]),
    Descriptor=#{top=>protocol_boundary,clock_proc=>boundary_clock,actors=>maps:get(actors,Network),
        actor_runtime=>true,eligible=>false,ordering=>per_logical_sender_destination,
        activation=>maps:get(activation,Network),inspection=>maps:get(inspection,Network),additional_state_bits=>Bits+maps:get(additional_state_bits,Network),
        arbitration_state_bits=>Bits,externals=>Groups,inputs=>Inputs,outputs=>Outputs},
    #plan{descriptor = Descriptor, pass_inputs = PassInputs, pass_outputs = PassOutputs}.

-doc "Returns the planned boundary interface and static arbitration facts. inspection remains the network's none/process mode; observation evidence and the source hash are added only by emission. Treat this descriptor as read-only.".
-spec descriptor(plan()) -> map().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns boundary clock, pin adapter and manifest files from an unchanged plan and the corresponding emitted network's inspection evidence. Reads templates without writing output, adding actual inspection evidence and the source hash to the descriptor. Network preview observations must remain independent of boundary ready; only the final transition consumes arbiter acceptance. No payload buffering or application eligibility is added.".
-spec emit(plan(), none | map()) -> hls_generated_files:output().
emit(#plan{descriptor = Descriptor = #{inputs := Inputs, outputs := Outputs, externals := Groups},
        pass_inputs = PassInputs, pass_outputs = PassOutputs}, Inspection) ->
    Source = source(Inputs, Outputs, PassInputs, PassOutputs, Groups),
    Manifest = Descriptor#{inspection := Inspection, dslx_sha256 => hls_generated_files:hash(Source)},
    #{files=>#{"boundary/boundary.x"=>Source,
        "boundary/protocol_boundary.sv"=>sv_protocol_ports:emit(pins(Inputs),pins(Outputs),"protocol_boundary","protocol_boundary_core"),
        "boundary/manifest.json"=>json:encode(Manifest)},result=>Manifest}.

%% Keep the preview/arbiter/commit schedule in DSLX; only static wiring varies.
-spec source([map()], [map()], [map()], [map()], [map()]) -> iodata().
source(Inputs, Outputs, PassInputs, PassOutputs, Groups) ->
    Multiple = [G || G = #{members := Members} <- Groups, length(Members) > 1],
    Directory = filename:join(code:priv_dir(hls_fabric), "xls/templates"),
    {ok, Template} = file:read_file(filename:join(Directory, "protocol_boundary.x.in")),
    {ok, Clock} = file:read_file(filename:join(Directory, "protocol_boundary_clock.x.in")),
    Bindings = [
        {<<"@@INPUT_FIELDS@@">>, fields(Inputs)},
        {<<"@@OUTPUT_FIELDS@@">>, fields(Outputs)},
        {<<"@@ARBITER_STATE@@">>, [[external(I), ": egress::State<", n(C), ">,\n"]
            || #{index := I, index_bits := C} <- Multiple]},
        {<<"@@PASS_INPUTS@@">>, [[Name, ": io.", Name, ",\n"]
            || #{name := Name} <- PassInputs]},
        {<<"@@ARBITER_STEPS@@">>, [arbiter(Group) || Group <- Multiple]},
        {<<"@@ACCEPTANCE@@">>, [acceptance(Group) || Group <- Groups]},
        {<<"@@ARBITER_UPDATES@@">>, [[external(I), ": merge_", n(I), ".state,\n"]
            || #{index := I} <- Multiple]},
        {<<"@@PASS_OUTPUTS@@">>, [[Name, ": preview.", Name, ",\n"]
            || #{name := Name} <- PassOutputs]},
        {<<"@@OBSERVATIONS@@">>, [observation(Group) || Group <- Groups]}
    ],
    [xls_template:render(Template, Bindings), Clock].

%% Producer bit zero is array element zero; sources retain frames until selected acceptance.
-spec arbiter(map()) -> iodata().
arbiter(#{index:=I,members:=Members}) ->
    ["let merge_",n(I)," = egress::tick(s.",external(I),", io.reset, ",
     lists:join(" ++ ",[["preview.",Name,"_valid"]||#{name:=Name}<-lists:reverse(Members)]),
     ", [",lists:join(", ",[["preview.",Name,"_data"]||#{name:=Name}<-Members]),"], io.",external(I),"_ready);\n"].

%% Singletons bypass selection entirely; no endpoint can acknowledge another's producer.
-spec acceptance(map()) -> iodata().
acceptance(#{members:=[]}) -> [];
acceptance(#{index:=I,members:=[#{name:=Name}]}) -> [Name,"_ready: io.",external(I),"_ready,\n"];
acceptance(#{index:=I,members:=Members}) ->
    [[Name,"_ready: merge_",n(I),".output.ready[",n(K),"+:u1],\n"]||{K,#{name:=Name}}<-lists:enumerate(0,Members)].

%% Empty declarations remain visible as an invalid zero stream for stable host binding.
-spec observation(map()) -> iodata().
observation(#{index:=I,members:=[]}) -> [external(I),"_valid: false, ",external(I),"_data: bits[128]:0,\n"];
observation(#{index:=I,members:=[#{name:=Name}]}) ->
    [external(I),"_valid: preview.",Name,"_valid, ",external(I),"_data: preview.",Name,"_data,\n"];
observation(#{index:=I}) ->
    [external(I),"_valid: merge_",n(I),".output.valid, ",external(I),"_data: merge_",n(I),".output.frame,\n"].

%% Preserve exact DSLX field order in the mechanical Verilog adapter.
-spec pins([map()]) -> [{string(),pos_integer()}].
pins(Fields) -> [{binary_to_list(Name),Width}||#{name:=Name,width:=Width}<-Fields].
%% Concrete widths and field order come from the checked boundary interface.
-spec fields([map()]) -> iodata().
fields(Fields) -> [[Key, ": bits[", n(Width), "],\n"]
    || #{name := Key, width := Width} <- Fields].
%% Endpoint indices follow canonical normalized topology order, never actor indices.
-spec external(non_neg_integer()) -> string().
external(I) -> "external_"++n(I).
%% Only elaborated integers enter generated identifiers and dimensions.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
