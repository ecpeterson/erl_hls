-module(hls_domain_endpoint_role).
-moduledoc "Connects one emitted source domain to independent mailbox TX/RX endpoints on its local clock. The topology supplies crossing identities; existing domain and endpoint cores retain all state and policy. Board builders add carrier framing and management outside this mechanical role. No peer lifecycle is sampled across boards.".

%% Compose existing emitted interfaces without recompiling their source.
-export([emit/3, emit/4]).
-export_type([domain/0, endpoint/0, endpoints/0, options/0, result/0]).

%% Ordered pins retain the widths supplied by existing emitted units.
-type ports() :: [{string(), pos_integer()}].

%% Only these fields are consumed from each retained hls_protocol_domains crossing.
-type crossing() :: #{
    index := non_neg_integer(),
    source_domain := non_neg_integer(),
    destination_domain := non_neg_integer()
}.

-doc "Fields consumed from a stream-mode hls_protocol_domains domain descriptor. The original descriptor may retain its other source/runtime metadata.".
-type domain() :: #{
    index := non_neg_integer(),
    mode := stream,
    interface := #{
        inputs := ports(),
        outputs := ports(),
        codecs := #{phase := hls_type:descriptor()}
    }
}.

-doc "Fields consumed from hls_domain_endpoint_build metadata; the supplied top module already implements the corresponding source-derived endpoint.".
-type endpoint() :: #{
    direction := hls_domain_endpoint_build:direction(),
    inputs := ports(),
    outputs := ports(),
    top_module := string(),
    cold_reset_pin := string(),
    local_ready_pin := string(),
    local_incarnation_pin := string()
}.

-doc "Existing TX/RX interfaces shared by all corresponding crossings of this role.".
-type endpoints() :: #{tx := endpoint(), rx := endpoint()}.

-doc "Optional checked HDL names. Defaults are endpoint_role_INDEX and domain_INDEX; endpoint module names come from their retained build metadata.".
-type options() :: #{top_module => string(), domain_module => string()}.

%% A physical directed crossing has only one local endpoint on a role.
-type instance() :: #{
    id := non_neg_integer(),
    kind := tx | rx,
    module := string(),
    inputs := ports(),
    outputs := ports()
}.

-doc "Exact public pins and instantiated module identities. Pins exclude clk, which clocks this role alone. The single generated file contains no storage, transport arbitration or session policy; dependencies are supplied separately by the caller.".
-type result() :: #{
    top_module := string(),
    domain_module := string(),
    domain_index := non_neg_integer(),
    inputs := ports(),
    outputs := ports(),
    endpoints := [instance()],
    source := string()
}.

-doc "Connects every crossing of one existing framed domain to its corresponding existing TX/RX module. Leaves complete host application/management streams and endpoint transport/management pins public. Domain reset retires local ownership through readiness/incarnation; only the common cold reset clears endpoints.".
-spec emit(domain(), [crossing()], endpoints()) ->
    hls_generated_files:output(result()).
emit(Domain, Crossings, Endpoints) -> emit(Domain, Crossings, Endpoints, #{}).

-doc "Composes under explicit checked module names. Rejects duplicate identities, mismatched crossing widths, missing lifecycle pins and unaccounted raw crossing pins before emitting RTL. Calls no source compiler or external tool and creates no same-clock dependency on the peer role.".
-spec emit(domain(), [crossing()], endpoints(), options()) ->
    hls_generated_files:output(result()).
emit(
    Domain = #{
        index := Index,
        mode := stream,
        interface := #{
            inputs := DomainInputs,
            outputs := DomainOutputs,
            codecs := #{phase := Phase}
        }
    },
    Crossings,
    Endpoints,
    Options
) ->
    Top = maps:get(top_module, Options, "endpoint_role_" ++ n(Index)),
    DomainModule = maps:get(domain_module, Options, "domain_" ++ n(Index)),
    lists:foreach(fun identifier/1, [Top, DomainModule]),
    Instances = instances(Index, Crossings, Endpoints),
    {PrivateInputs, PrivateOutputs} = validate_domain(
        DomainInputs, DomainOutputs, Instances, Phase
    ),
    Prefix = domain_prefix(Index),
    Inputs =
        [{"reset", 1}] ++
            [
                {Prefix ++ Name, Width}
             || {Name, Width} <- DomainInputs,
                Name =/= "reset",
                not lists:keymember(Name, 1, PrivateInputs)
            ] ++
            lists:append([
                [
                    {endpoint_prefix(Id) ++ Name, Width}
                 || {Name, Width} <- Ps, not private_input(Name, Kind)
                ]
             || #{id := Id, kind := Kind, inputs := Ps} <- Instances
            ]),
    Outputs =
        [
            {Prefix ++ Name, Width}
         || {Name, Width} <- DomainOutputs,
            not lists:keymember(Name, 1, PrivateOutputs)
        ] ++
            lists:append([
                [
                    {endpoint_prefix(Id) ++ Name, Width}
                 || {Name, Width} <- Ps, not private_output(Name, Kind)
                ]
             || #{id := Id, kind := Kind, outputs := Ps} <- Instances
            ]),
    validate_ports(Inputs, Outputs),
    Text = [
        "// Local domain and independent endpoint instances; no carrier or ownership policy.\n",
        "module ",
        Top,
        "(input wire clk,\n",
        lists:join(
            ",\n",
            [port("input", P) || P <- Inputs] ++
                [port("output", P) || P <- Outputs]
        ),
        "\n);\n",
        [wire({Prefix ++ Name, Width}) || {Name, Width} <- PrivateInputs ++ PrivateOutputs],
        domain_instance(DomainModule, Prefix, DomainInputs, DomainOutputs),
        [endpoint_instance(Instance, Domain, Phase) || Instance <- Instances],
        "endmodule\n"
    ],
    Source = Top ++ ".sv",
    #{
        files => #{Source => Text},
        result => #{
            top_module => Top,
            domain_module => DomainModule,
            domain_index => Index,
            inputs => Inputs,
            outputs => Outputs,
            endpoints => Instances,
            source => Source
        }
    }.

%% Source crossing IDs remain stable across both separately clocked roles.
-spec instances(non_neg_integer(), [crossing()], endpoints()) -> [instance()].
instances(Index, Crossings, Endpoints) ->
    Ids = [Id || #{index := Id} <- Crossings],
    require(length(Ids) =:= length(lists:usort(Ids)), duplicate_crossing),
    [
        begin
            require(Source =/= Destination, local_crossing),
            Kind =
                case Source of
                    Index -> tx;
                    _ -> rx
                end,
            Endpoint =
                #{
                    direction := ActualKind,
                    top_module := Module,
                    inputs := Inputs,
                    outputs := Outputs
                } = maps:get(Kind, Endpoints),
            require(ActualKind =:= Kind, endpoint_direction),
            #{
                cold_reset_pin := "reset",
                local_ready_pin := "local_ready",
                local_incarnation_pin := "local_incarnation"
            } = Endpoint,
            identifier(Module),
            validate_ports(Inputs, Outputs),
            require(
                lists:all(
                    fun(P) -> lists:member(P, Inputs) end,
                    [{"reset", 1}, {"local_ready", 1}, {"local_incarnation", 64}]
                ),
                endpoint_lifecycle
            ),
            #{id => Id, kind => Kind, module => Module, inputs => Inputs, outputs => Outputs}
        end
     || #{index := Id, source_domain := Source, destination_domain := Destination} <- Crossings,
        Source =:= Index orelse Destination =:= Index
    ].

%% Exact crossing wires become private; local RX fault/free observations remain public diagnostics.
-spec validate_domain(ports(), ports(), [instance()], hls_type:descriptor()) -> {ports(), ports()}.
validate_domain(Inputs, Outputs, Instances, Phase) ->
    validate_ports(Inputs, Outputs),
    require(
        lists:all(
            fun(P) -> lists:member(P, Inputs) end,
            [{"reset", 1}, {"domain_reset", 1}]
        ),
        domain_reset
    ),
    require(
        lists:all(
            fun(P) -> lists:member(P, Outputs) end,
            [{"domain_phase", hls_type:width(Phase)}, {"domain_current", 64}]
        ),
        domain_lifecycle
    ),
    Expected = [crossing_ports(I) || I <- Instances],
    PrivateInputs = lists:append([Ps || {Ps, _} <- Expected]),
    PrivateOutputs = lists:append([Ps || {_, Ps} <- Expected]),
    require(
        lists:sort([P || P = {Name, _} <- Inputs, remote_input(Name)]) =:=
            lists:sort(PrivateInputs),
        crossing_inputs
    ),
    require(
        lists:sort([
            P
         || P = {Name, _} <- Outputs,
            lists:keymember(Name, 1, PrivateOutputs)
        ]) =:= lists:sort(PrivateOutputs),
        crossing_outputs
    ),
    Diagnostics = [
        P
     || P = {Name, _} <- Outputs,
        remote_output(Name),
        not lists:keymember(Name, 1, PrivateOutputs)
    ],
    FaultPins = [{remote(Id, "fault", output), 1} || #{id := Id, kind := rx} <- Instances],
    FreePins = [remote(Id, "free", output) || #{id := Id, kind := rx} <- Instances],
    require(
        lists:all(
            fun(P = {Name, _}) ->
                lists:member(P, FaultPins) orelse lists:member(Name, FreePins)
            end,
            Diagnostics
        ),
        crossing_diagnostics
    ),
    {PrivateInputs, PrivateOutputs}.

%% Endpoint interfaces supply frame/slot widths; scalar handshakes remain explicit.
-spec crossing_ports(instance()) -> {ports(), ports()}.
crossing_ports(#{id := Id, kind := tx, inputs := Inputs, outputs := Outputs}) ->
    require(lists:member({"source_ready", 1}, Outputs), endpoint_source_ready),
    require(lists:member({"source_valid", 1}, Inputs), endpoint_source_valid),
    {[{remote(Id, "ready", input), 1}], [
        {remote(Id, Suffix, output), width("source_" ++ Suffix, Inputs)}
     || Suffix <- ["valid", "slot", "frame"]
    ]};
crossing_ports(#{id := Id, kind := rx, inputs := Inputs, outputs := Outputs}) ->
    require(lists:member({"destination_ready", 1}, Inputs), endpoint_destination_ready),
    require(lists:member({"destination_valid", 1}, Outputs), endpoint_destination_valid),
    {
        [
            {remote(Id, Suffix, input), width("destination_" ++ Suffix, Outputs)}
         || Suffix <- ["valid", "slot", "frame"]
        ],
        [{remote(Id, "ready", output), 1}]
    }.

%% Missing fields fail before emitting an undeclared or truncated connection.
-spec width(string(), ports()) -> pos_integer().
width(Name, Ports) ->
    case lists:keyfind(Name, 1, Ports) of
        {Name, Width} -> Width;
        false -> erlang:error({endpoint_role, {missing_pin, Name}})
    end.

%% Child interfaces and the combined top must contain legal distinct names and positive widths.
-spec validate_ports(ports(), ports()) -> ok.
validate_ports(Inputs, Outputs) ->
    Names = [Name || {Name, _} <- Inputs ++ Outputs],
    lists:foreach(fun identifier/1, Names),
    require(not lists:member("clk", Names), reserved_clock),
    require(length(Names) =:= length(lists:usort(Names)), duplicate_pin),
    require(lists:all(fun({_, Width}) -> Width > 0 end, Inputs ++ Outputs), pin_width).

%% This namespace is checked exhaustively against the derived private input list.
-spec remote_input(string()) -> boolean().
remote_input(Name) -> lists:prefix("remote_", Name).

%% This namespace is checked against exact crossing wires and local RX diagnostic names.
-spec remote_output(string()) -> boolean().
remote_output(Name) -> lists:prefix("app_remote_", Name).

%% Transport and binding commands stay public; only local lifecycle and actor handshakes are wired.
-spec private_input(string(), tx | rx) -> boolean().
private_input(Name, Kind) ->
    lists:member(
        Name,
        ["reset", "local_ready", "local_incarnation"] ++
            case Kind of
                tx -> ["source_valid", "source_slot", "source_frame"];
                rx -> ["destination_ready"]
            end
    ).

%% Capture diagnostics remain visible without allowing transport to bypass ownership.
-spec private_output(string(), tx | rx) -> boolean().
private_output(Name, tx) ->
    Name =:= "source_ready";
private_output(Name, rx) ->
    lists:member(Name, ["destination_valid", "destination_slot", "destination_frame"]).

%% Cold reset is shared; domain_reset stays a separate host-visible local input.
-spec domain_instance(string(), string(), ports(), ports()) -> iodata().
domain_instance(Module, Prefix, Inputs, Outputs) ->
    [
        Module,
        " local_domain(.clk(clk),\n",
        lists:join(
            ",\n",
            [
                connect(
                    Name,
                    case Name of
                        "reset" -> "reset";
                        _ -> Prefix ++ Name
                    end
                )
             || {Name, _} <- Inputs
            ] ++
                [connect(Name, Prefix ++ Name) || {Name, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% The source-derived phase encoding avoids a second lifecycle tag table.
-spec endpoint_instance(instance(), domain(), hls_type:descriptor()) -> iodata().
endpoint_instance(
    #{
        id := Id,
        kind := Kind,
        module := Module,
        inputs := Inputs,
        outputs := Outputs
    },
    #{index := Index},
    Phase
) ->
    Width = hls_type:width(Phase),
    <<Ready:Width>> = hls_type:pack(ready, Phase),
    Prefix = domain_prefix(Index),
    Live = [
        "(!reset && !",
        Prefix,
        "domain_reset && ",
        Prefix,
        "domain_phase == ",
        n(Width),
        "'d",
        n(Ready),
        " && ",
        Prefix,
        "domain_current != 64'd0)"
    ],
    [
        Module,
        " endpoint_",
        n(Id),
        "(.clk(clk),\n",
        lists:join(
            ",\n",
            [
                connect(Name, endpoint_input(Name, Kind, Id, Prefix, Live))
             || {Name, _} <- Inputs
            ] ++
                [connect(Name, endpoint_output(Name, Kind, Id, Prefix)) || {Name, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% Only the owning domain contributes liveness/incarnation; receiver confirmation remains a command.
-spec endpoint_input(string(), tx | rx, non_neg_integer(), string(), iodata()) -> iodata().
endpoint_input("reset", _, _, _, _) -> "reset";
endpoint_input("local_ready", _, _, _, Live) -> Live;
endpoint_input("local_incarnation", _, _, Prefix, _) -> Prefix ++ "domain_current";
endpoint_input("source_valid", tx, Id, Prefix, _) -> Prefix ++ remote(Id, "valid", output);
endpoint_input("source_slot", tx, Id, Prefix, _) -> Prefix ++ remote(Id, "slot", output);
endpoint_input("source_frame", tx, Id, Prefix, _) -> Prefix ++ remote(Id, "frame", output);
endpoint_input("destination_ready", rx, Id, Prefix, _) -> Prefix ++ remote(Id, "ready", output);
endpoint_input(Name, _, Id, _, _) -> endpoint_prefix(Id) ++ Name.

%% Endpoint ownership alone controls publication acceptance and native destination delivery.
-spec endpoint_output(string(), tx | rx, non_neg_integer(), string()) -> string().
endpoint_output("source_ready", tx, Id, Prefix) -> Prefix ++ remote(Id, "ready", input);
endpoint_output("destination_valid", rx, Id, Prefix) -> Prefix ++ remote(Id, "valid", input);
endpoint_output("destination_slot", rx, Id, Prefix) -> Prefix ++ remote(Id, "slot", input);
endpoint_output("destination_frame", rx, Id, Prefix) -> Prefix ++ remote(Id, "frame", input);
endpoint_output(Name, _, Id, _) -> endpoint_prefix(Id) ++ Name.

%% Names retain the source crossing index rather than assigning board-local aliases.
-spec remote(non_neg_integer(), string(), input | output) -> string().
remote(Id, Suffix, input) -> "remote_" ++ n(Id) ++ "_" ++ Suffix;
remote(Id, Suffix, output) -> "app_remote_" ++ n(Id) ++ "_" ++ Suffix.

%% One top can be embedded without renaming its existing framed domain pins.
-spec domain_prefix(non_neg_integer()) -> string().
domain_prefix(Index) -> "domain_" ++ n(Index) ++ "_".

%% Management and carrier users address endpoints by the same directed crossing identity.
-spec endpoint_prefix(non_neg_integer()) -> string().
endpoint_prefix(Id) -> "endpoint_" ++ n(Id) ++ "_".

%% No application string may inject HDL into module or signal names.
-spec identifier(string()) -> ok.
identifier(Name) ->
    require(
        re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]) =:= match,
        {identifier, Name}
    ).

%% Preserve normal scalar syntax while rendering declared vector widths exactly.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port(Direction, {Name, 1}) -> [Direction, " wire ", Name];
port(Direction, {Name, Width}) -> [Direction, " wire [", n(Width - 1), ":0] ", Name].

%% Only connected raw crossing ports require new wires.
-spec wire({string(), pos_integer()}) -> iodata().
wire({Name, 1}) -> ["wire ", Name, ";\n"];
wire({Name, Width}) -> ["wire [", n(Width - 1), ":0] ", Name, ";\n"].

%% Named associations decouple composition from generated module declaration order.
-spec connect(string(), iodata()) -> iodata().
connect(Name, Value) -> [".", Name, "(", Value, ")"].

%% All rendered integers are checked static indices, widths or source enum encodings.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).

%% Validation errors identify the failed interface contract before any artifact is emitted.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> erlang:error({endpoint_role, Reason}).
