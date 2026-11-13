-module(phi_domain_repetition_fixture).
-moduledoc "Application-owned repetition fixture for current framed recovery domains. The source actors and numerical boundary are unchanged; only host setup, addressed control and output naming differ from the ordinary topology. The emitted two-role composition is a same-clock local witness, not a distributed board image.".

%% Trusted source topology, selected fixture and portable build bundle.
-export([topology/2, configuration/3, write/2, write/4, write_metadata/1]).

%% Existing finite ordinary-BEAM reference.
-export([oracle/2]).

-doc "Returns the ordinary repetition graph with silent startup, one addressed command target per family, and distinct correction/status external streams. The caller must submit retained setup messages after binding fresh domains and before starting Phi; dropping startup without that setup would change the workload.".
-spec topology(pos_integer(), hls_nums:u32()) -> hls_topology:spec().
topology(Width, Threshold) ->
    Original = #{route_relations := Relations} = phi_repetition_topology:topology(Width, Threshold),
    Original#{
        startup := [],
        ingresses := [{control_router, {rectangle, [Width, 1]}, [
            target(data, [phenom_config, noise_cutoff, pauli_query, pauli_update]),
            target(syndrome, [phenom_config, noise_cutoff]),
            target(phi, [phi_config])
        ]}],
        externals := [
            {decoder_corrections, out, [phi_correction]},
            {decoder_status, out, [phi_status]},
            {data_measurements, out, [pauli_reply]}
        ],
        route_relations := [separate_output(Relation) || Relation <- Relations]
    }.

-doc "Returns source configuration, two-role placement and host setup metadata for widths 2..16 with a nonempty contiguous split. Inspection is none or process. Actor indices come from ordinary topology elaboration; both roles share one required restart group. The selected finite workload has cutoff eight and readout request 123, matching oracle/2.".
-spec configuration(pos_integer(), pos_integer(), none | process) ->
    {hls_source_config:network(), hls_protocol_domains:placement(), map()}.
configuration(Width, Split, Inspection) when
    Width >= 2, Width =< 16, Split > 0, Split < Width,
    (Inspection =:= none orelse Inspection =:= process)
->
    {application, Base} = phi_protocol_config:repetition(Width, #{}),
    #{sources := Sources} = Base,
    Fixture = proplists:get_value(source, ?MODULE:module_info(compile)),
    true = is_list(Fixture),
    Config = maps:without([device, host], Base#{
        sources := Sources ++ [{Fixture, []}],
        topology := {?MODULE, topology, [Width, 16#80000000]},
        control => rectangle,
        activation => automatic,
        frame_payload_words => 20,
        inspection => Inspection
    }),
    Plan = hls_protocol_topology:elaborate(
        hls_topology:normalize(topology(Width, 16#80000000)), 3 * Width
    ),
    #{actors := Actors} = Plan,
    Indexed = [#{id => Id, index => I, module => Module,
        domain => role(X, Split)}
        || {I, #{id := Id = {_, X, 0}, module := Module}} <- lists:enumerate(0, Actors)],
    Placement = #{domains => [{Role, [I || #{index := I, domain := D} <- Indexed, D =:= Role]}
        || Role <- [a, b]], restart_groups => [[a, b]]},
    #{startup := Startup} = hls_topology:normalize(phi_repetition_topology:topology(Width)),
    Metadata = #{version => 1, width => Width, split => Split,
        inspection => Inspection, actors => Indexed, placement => Placement,
        original_startup => Startup, host_setup => setup(Startup, Indexed, 8),
        cutoff => 8, request => 123, basis => x,
        memory_streams => #{decoder_corrections => decoder_events,
            decoder_status => decoder_events, data_measurements => data_measurements},
        reference => {phi_protocol_repetition_fixture, oracle, 2},
        execution => same_clock_local_composition, physical_board_image => false},
    {Config, Placement, Metadata};
configuration(Width, Split, Inspection) ->
    error({domain_repetition_options, Width, Split, Inspection}).

-doc "Writes the selected N8/4+4 framed recovery-domain bundle and fixture.etf, with optional matched process inspection. Does not invoke XLS, synthesize, contact boards or claim physical deployment.".
-spec write(file:filename(), none | process) -> map().
write(Directory, Inspection) -> write(Directory, 8, 4, Inspection).

-doc "Writes the requested width/split through hls_protocol_domains:write_stream/3, retaining explicit setup in fixture.etf beside the ordinary source-build manifest. Directory must be fresh. The source-build compiler remains the external tool boundary.".
-spec write(file:filename(), pos_integer(), pos_integer(), none | process) -> map().
write(Directory, Width, Split, Inspection) ->
    {Config, Placement, Metadata} = configuration(Width, Split, Inspection),
    Build = hls_protocol_domains:write_stream(Config, Placement, Directory),
    ok = file:write_file(filename:join(Directory, "fixture.etf"), term_to_binary(Metadata), [exclusive]),
    ok = write_metadata(Directory),
    Build.

-doc "Writes only a missing fixture.json from the retained fixture.etf and interface.etf of a completed emission. Does not reload source, re-elaborate or replace an existing metadata file.".
-spec write_metadata(file:filename()) -> ok.
write_metadata(Directory) ->
    {ok, FixtureBytes} = file:read_file(filename:join(Directory, "fixture.etf")),
    Metadata = binary_to_term(FixtureBytes),
    {ok, InterfaceBytes} = file:read_file(filename:join(Directory, "interface.etf")),
    #{domains := Domains, crossings := Crossings, frame_payload_words := Words} =
        binary_to_term(InterfaceBytes),
    Public = Metadata#{frame_words => Words + 1,
        domains => [#{id => Id, index => I, actors => Is} ||
            #{id := Id, index := I, actors := Is} <- Domains],
        channels => [#{index => I, source_domain => S, destination_domain => D} ||
            #{index := I, source_domain := S, destination_domain := D} <- Crossings]},
    ok = file:write_file(filename:join(Directory, "fixture.json"),
        json:encode(json_value(Public)), [exclusive]).

-doc "Runs the existing ordinary-BEAM finite repetition memory reference, including correction feedback and canonical readout. Writes its original oracle.json; this is a finite witness, not a convergence or recovery proof.".
-spec oracle(file:filename(), pos_integer()) -> ok.
oracle(Stage, Width) -> phi_protocol_repetition_fixture:oracle(Stage, Width).

%% A selector chooses one family, and each coordinate then chooses exactly one actor.
-spec target(atom(), [atom()]) -> tuple().
target(Family, Schemas) ->
    {Family, Schemas, [{family, Family, {embed, [1, 1], [0, 0]}}]}.

%% Output identity is transport bookkeeping; the original actor terms remain unchanged.
-spec separate_output(tuple()) -> tuple().
separate_output({{phi, correction}, [{external, decoder_events}]}) ->
    {{phi, correction}, [{external, decoder_corrections}]};
separate_output({{phi, status}, [{external, decoder_events}]}) ->
    {{phi, status}, [{external, decoder_status}]};
separate_output(Relation) -> Relation.

%% Board-role labels are spatial ownership, not an assumed source enumeration order.
-spec role(non_neg_integer(), pos_integer()) -> a | b.
role(X, Split) when X < Split -> a;
role(_, _) -> b.

%% Prepare all noise actors and their cutoff before releasing any Phi actor into the graph.
-spec setup([map()], [map()], hls_nums:u32()) -> map().
setup(Startup, Actors, Cutoff) ->
    Index = maps:from_list([{maps:get(id, A), A} || A <- Actors]),
    Configurations = [{Id, Message} || #{target := Id, messages := Messages} <- Startup,
        Message <- Messages],
    Prepare = [command(Id, Message, Index) || {Id = {Family, _, _}, Message} <- Configurations,
        Family =/= phi] ++
        [command(Id, {noise_cutoff, Cutoff}, Index) || #{id := Id = {Family, _, _}} <- Actors,
            Family =:= data orelse Family =:= syndrome],
    Start = [command(Id, Message, Index) || {Id = {phi, _, _}, Message} <- Configurations],
    #{prepare => Prepare, start => Start}.

%% Retain logical actor identity for runtime APIs and its exact index for public-pin witnesses.
-spec command(tuple(), tuple(), map()) -> map().
command(Id = {Family, X, 0}, Message, Index) ->
    #{index := I, domain := Domain} = maps:get(Id, Index),
    #{actor => Id, actor_index => I, domain => Domain, target => Family,
        rectangle => {X, 0, X, 0}, message => Message}.

%% JSON copies identify public pins and workload terms; the runtime consumes the original ETF.
-spec json_value(term()) -> term().
json_value(Value) when is_map(Value) -> maps:map(fun(_, V) -> json_value(V) end, Value);
json_value(Value) when is_tuple(Value) -> [json_value(V) || V <- tuple_to_list(Value)];
json_value(Value) when is_list(Value) -> [json_value(V) || V <- Value];
json_value(Value) -> Value.
