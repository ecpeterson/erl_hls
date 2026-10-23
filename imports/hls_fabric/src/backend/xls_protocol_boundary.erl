-module(xls_protocol_boundary).
-moduledoc "Wires declared external endpoints to static DSLX arbiters around the source-network transition.".
-export([write/2]).

-doc "Emits a fresh boundary clock, mechanical pin adapter and manifest for hls_protocol_boundary's checked plan. Reuses the network state and one small arbitration state per endpoint with multiple producers. Network preview observations must be independent of boundary ready; only the final transition consumes arbiter acceptance. No payload buffering or application eligibility is added.".
-spec write(map(),file:filename()) -> map().
write(#{network:=Network=#{inputs:=NetworkInputs,outputs:=NetworkOutputs,boundaries:=Boundaries},externals:=Groups},Directory) ->
    Path=filename:join(Directory,"boundary"),ok=file:make_dir(Path),
    BoundaryNames=lists:append([[<<Name/binary,"_ready">>,<<Name/binary,"_valid">>,<<Name/binary,"_data">>]||#{name:=Name}<-Boundaries]),
    PassInputs=[P||P=#{name:=Name}<-NetworkInputs,not lists:member(Name,BoundaryNames)],
    PassOutputs=[P||P=#{name:=Name}<-NetworkOutputs,not lists:member(Name,BoundaryNames)],
    Inputs=PassInputs++[#{name=>list_to_binary(external(I)++"_ready"),width=>1}||#{index:=I}<-Groups],
    Outputs=PassOutputs++lists:append([[#{name=>list_to_binary(external(I)++"_valid"),width=>1},
        #{name=>list_to_binary(external(I)++"_data"),width=>128}]||#{index:=I}<-Groups]),
    Multiple=[G||G=#{members:=Ms}<-Groups,length(Ms)>1],
    {ok,Clock}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_boundary_clock.x.in")),
    Source=["import network;\nimport protocol_egress as egress;\n",structure("Inputs",Inputs),structure("Outputs",Outputs),
        "// Network state and independent endpoint ownership; no copied frame payloads.\npub struct State { network: network::State,\n",
        [[external(I),": egress::State<",n(C),">,\n"]||#{index:=I,index_bits:=C}<-Multiple],"}\n",
        "// Next state and current boundary observations.\npub struct Tick { state: State, output: Outputs }\n",
        "// Preview ignores sink readiness; only the final transition retires publications.\n",
        "pub fn tick(s: State, io: Inputs) -> Tick {\nlet offer = network::Inputs {\n",
        [[Name,": io.",Name,",\n"]||#{name:=Name}<-PassInputs],"..zero!<network::Inputs>() };\n",
        "let preview = network::tick(s.network, offer).output;\n",
        [arbiter(G)||G<-Multiple],
        "let step = network::tick(s.network, network::Inputs {\n",
        [acceptance(G)||G<-Groups],"..offer });\n",
        "Tick { state: State { network: step.state,\n",
        [[external(I),": merge_",n(I),".state,\n"]||#{index:=I}<-Multiple],"}, output: Outputs {\n",
        [[Name,": preview.",Name,",\n"]||#{name:=Name}<-PassOutputs],
        [observation(G)||G<-Groups],"} } }\n",Clock],
    ok=file:write_file(filename:join(Path,"boundary.x"),Source,[exclusive]),
    ok=sv_protocol_ports:write(pins(Inputs),pins(Outputs),filename:join(Path,"protocol_boundary.sv"),"protocol_boundary","protocol_boundary_core"),
    Bits=lists:sum([N||#{state_bits:=N}<-Groups]),
    Manifest=#{top=>protocol_boundary,clock_proc=>boundary_clock,actors=>maps:get(actors,Network),
        actor_runtime=>true,eligible=>false,ordering=>per_logical_sender_destination,
        activation=>maps:get(activation,Network),inspection=>maps:get(inspection,Network),additional_state_bits=>Bits+maps:get(additional_state_bits,Network),
        arbitration_state_bits=>Bits,externals=>Groups,inputs=>Inputs,outputs=>Outputs,
        dslx_sha256=>binary:encode_hex(crypto:hash(sha256,Source),lowercase)},
    ok=file:write_file(filename:join(Path,"manifest.json"),json:encode(Manifest),[exclusive]),Manifest.

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
%% Concrete widths come from the already checked network and declared endpoints.
-spec structure(string(),[map()]) -> iodata().
structure(Name,Fields) -> ["// Sampled application boundary pins.\npub struct ",Name," {\n",
    [[Key,": bits[",n(W),"],\n"]||#{name:=Key,width:=W}<-Fields],"}\n"].
%% Endpoint indices follow canonical normalized topology order, never actor indices.
-spec external(non_neg_integer()) -> string().
external(I) -> "external_"++n(I).
%% Only elaborated integers enter generated identifiers and dimensions.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
