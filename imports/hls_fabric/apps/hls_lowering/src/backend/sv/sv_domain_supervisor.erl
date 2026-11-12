-module(sv_domain_supervisor).
-moduledoc "Stateless wiring between one compiled supervisor and independent raw domain cores. Lifecycle authority connects only to the supervisor; application pins remain separate per child and close whenever the parent is not ready.".

%% Public pin layout and structural composition.
-export([ports/3, emit/3, stream_ports/3, emit_stream/3]).

%% Source-derived child pin interfaces with elaborated HDL-safe indices.
-type children() :: [
    #{id := atom(), index := non_neg_integer(), interface := hls_protocol_domain:result()}
].
%% Named finite unsigned hardware fields in sampled struct order.
-type ports() :: [{string(), pos_integer()}].

-doc "Returns parent management/grant pins and independent namespaced child application pins. Child management inputs are owned exclusively by the compiled supervisor and never exposed as host controls.".
-spec ports(children(), ports(), ports()) -> {ports(), ports()}.
ports(Children, Inputs, Outputs) ->
    ParentInputs = [{N, W} || {N, W} <- Inputs, not child_name(N)],
    ParentOutputs = [{N, W} || {N, W} <- Outputs, not child_name(N)],
    ChildInputs = lists:append([
        [{prefix(I) ++ N, W} || {N, W} <- Ps, application_input(N)]
     || #{index := I, interface := #{inputs := Ps}} <- Children
    ]),
    ChildOutputs = lists:append([
        [{prefix(I) ++ N, W} || {N, W} <- Ps]
     || #{index := I, interface := #{outputs := Ps}} <- Children
    ]),
    PublicInputs = ParentInputs ++ ChildInputs,
    PublicOutputs = ParentOutputs ++ ChildOutputs,
    unique_ports(PublicInputs, PublicOutputs),
    {PublicInputs, PublicOutputs}.

-doc "Renders mechanical RTL connectivity only. Each child retains its own clocked state; no application packet buffer or scheduler is added. Parent closure gates both external directions before the child retirement scan completes.".
-spec emit(children(), ports(), ports()) -> iodata().
emit(Children, ControlInputs, ControlOutputs) ->
    unique_ports(ControlInputs, ControlOutputs),
    {Inputs, Outputs} = ports(Children, ControlInputs, ControlOutputs),
    [
        "// Composition and pin gating only; lifecycle policy is compiled Erlang.\n",
        "module protocol_supervisor(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [[wire({N, W}) || {N, W} <- ControlOutputs, child_name(N)]],
        [child_wires(C) || C <- Children],
        "supervisor_control control(.clk(clk),\n",
        lists:join(
            ",\n",
            [connection(N, control_input(N)) || {N, _} <- ControlInputs] ++
                [connection(N, N) || {N, _} <- ControlOutputs]
        ),
        "\n);\n",
        [child_instance(C) || C <- Children],
        "endmodule\n"
    ].

%% Whole words distinguish generated child pins from parent management fields.
-spec child_name(string()) -> boolean().
child_name(Name) -> lists:prefix("child_", Name).

%% Direct child lifecycle controls cannot bypass its supervisor authority.
-spec application_input(string()) -> boolean().
application_input(Name) ->
    not lists:member(Name, [
        "reset",
        "management_valid",
        "management_op",
        "expected",
        "target",
        "transition",
        "management_fault"
    ]).

%% Numeric elaboration indices are valid HDL components independently of source atom names.
-spec prefix(non_neg_integer()) -> string().
prefix(I) -> "child_" ++ integer_to_list(I) ++ "_".

%% Core observations are separately named so parent gating does not hide lifecycle evidence.
-spec child_wires(#{
    id := atom(), index := non_neg_integer(), interface := hls_protocol_domain:result()
}) -> iodata().
child_wires(#{index := I, interface := #{outputs := Outputs}}) ->
    [
        [
            wire({"raw_" ++ prefix(I) ++ N, W}),
            "assign ",
            prefix(I),
            N,
            " = ",
            case lists:prefix("app_", N) of
                true -> ["domain_admission ? raw_", prefix(I), N, " : ", integer_to_list(W), "'d0"];
                false -> ["raw_", prefix(I), N]
            end,
            ";\n"
        ]
     || {N, W} <- Outputs
    ].

%% The controller consumes lifecycle snapshots, never gated application outputs.
-spec control_input(string()) -> string().
control_input(Name) ->
    case
        re:run(Name, "^(child_[0-9]+_)observed_(phase|current|previous|target|transition|fault)$", [
            {capture, [1, 2], list}
        ])
    of
        {match, [Prefix, Field]} -> "raw_" ++ Prefix ++ "domain_" ++ Field;
        nomatch -> Name
    end.

%% Parent reset and grant ownership surround every independent child domain instance.
-spec child_instance(#{
    id := atom(), index := non_neg_integer(), interface := hls_protocol_domain:result()
}) -> iodata().
child_instance(#{index := I, interface := #{inputs := Inputs, outputs := Outputs}}) ->
    Name = "child_" ++ integer_to_list(I),
    [
        Name,
        " instance_",
        integer_to_list(I),
        "(.clk(clk),\n",
        lists:join(
            ",\n",
            [connection(N, child_input(I, N, W)) || {N, W} <- Inputs] ++
                [connection(N, "raw_" ++ prefix(I) ++ N) || {N, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% Parent closure masks ingress and downstream acceptance without changing child payloads.
-spec child_input(non_neg_integer(), string(), pos_integer()) -> iodata().
child_input(_I, "reset", _) ->
    "(reset || children_reset)";
child_input(I, N, W) ->
    case N =:= "ingress_valid" orelse lists:suffix("_ready", N) of
        true -> ["(domain_admission ? ", prefix(I), N, " : ", integer_to_list(W), "'d0)"];
        false -> [prefix(I), N]
    end.

%% Named associations preserve the generated wrapper's field order independently of text layout.
-spec connection(string(), iodata()) -> iodata().
connection(Name, Value) -> [".", Name, "(", Value, ")"].

%% Declarations retain exact widths, including scalar handshake fields.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port(Direction, {Name, 1}) -> [Direction, " wire ", Name];
port(Direction, {Name, W}) -> [Direction, " wire [", integer_to_list(W - 1), ":0] ", Name].

%% Internal outputs use wires only; storage belongs to the compiled cores.
-spec wire({string(), pos_integer()}) -> iodata().
wire({Name, 1}) -> ["wire ", Name, ";\n"];
wire({Name, W}) -> ["wire [", integer_to_list(W - 1), ":0] ", Name, ";\n"].

%% A field cannot simultaneously name a control input, output or duplicate public pin.
-spec unique_ports(ports(), ports()) -> ok.
unique_ports(Inputs, Outputs) ->
    Names = [N || {N, _} <- Inputs ++ Outputs],
    Duplicates = lists:usort(Names -- lists:usort(Names)),
    case Duplicates of
        [] -> ok;
        _ -> error({duplicate_supervisor_ports, Duplicates})
    end.

-doc "Returns raw parent control pins and separate framed child lanes. Private supervisor authority/reset pins are wired internally; stream session reset stays distinct from child reset.".
-spec stream_ports(children(), ports(), ports()) -> {ports(), ports()}.
stream_ports(Children, Inputs, Outputs) ->
    ParentInputs = [{N, W} || {N, W} <- Inputs, not child_name(N)],
    ParentOutputs = [{N, W} || {N, W} <- Outputs, not child_name(N)],
    ChildInputs = lists:append([
        [
            {prefix(I) ++ N, W}
         || {N, W} <- Ps,
            N =/= "reset",
            not lists:prefix("supervisor_", N)
        ]
     || #{index := I, interface := #{inputs := Ps}} <- Children
    ]),
    ChildOutputs = lists:append([
        [{prefix(I) ++ N, W} || {N, W} <- Ps]
     || #{index := I, interface := #{outputs := Ps}} <- Children
    ]),
    PublicInputs = ParentInputs ++ ChildInputs,
    PublicOutputs = ParentOutputs ++ ChildOutputs,
    unique_ports(PublicInputs, PublicOutputs),
    {PublicInputs, PublicOutputs}.

-doc "Connects one source-defined supervisor to independent framed child cores. Transport buffers and retirement receipts survive parent-driven child reset; only global reset clears them. Host backpressure never owns supervisor control.".
-spec emit_stream(children(), ports(), ports()) -> iodata().
emit_stream(Children, ControlInputs, ControlOutputs) ->
    {Inputs, Outputs} = stream_ports(Children, ControlInputs, ControlOutputs),
    [
        "// Stateless composition of autonomous control and independent framed domains.\n",
        "module protocol_supervisor_stream_raw(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [wire({"control_" ++ N, W}) || {N, W} <- ControlOutputs, child_name(N)],
        "supervisor_control control(.clk(clk),\n",
        lists:join(
            ",\n",
            [connection(N, stream_control_input(N)) || {N, _} <- ControlInputs] ++
                [
                    connection(
                        N,
                        case child_name(N) of
                            true -> "control_" ++ N;
                            false -> N
                        end
                    )
                 || {N, _} <- ControlOutputs
                ]
        ),
        "\n);\n",
        [stream_child(C) || C <- Children],
        "endmodule\n"
    ].

%% The scanner consumes actual lifecycle outputs even if a host lane is stalled.
-spec stream_control_input(string()) -> string().
stream_control_input(Name) ->
    case
        re:run(
            Name,
            "^(child_[0-9]+_)observed_(phase|current|previous|target|transition|fault)$",
            [{capture, [1, 2], list}]
        )
    of
        {match, [Prefix, Field]} -> Prefix ++ "domain_" ++ Field;
        nomatch -> Name
    end.

%% Each framed child compiles the same domain once; no simulator or host interprets its local commands.
-spec stream_child(#{
    id := atom(), index := non_neg_integer(), interface := hls_protocol_domain:result()
}) -> iodata().
stream_child(#{index := I, interface := #{inputs := Inputs, outputs := Outputs}}) ->
    [
        "child_",
        integer_to_list(I),
        " instance_",
        integer_to_list(I),
        "(.clk(clk),\n",
        lists:join(
            ",\n",
            [connection(N, stream_child_input(I, N)) || {N, _} <- Inputs] ++
                [connection(N, prefix(I) ++ N) || {N, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% Only cold reset clears transport evidence; subtree reset is sampled inside the domain.
-spec stream_child_input(non_neg_integer(), string()) -> string().
stream_child_input(_, "reset") -> "reset";
stream_child_input(_, "supervisor_reset") -> "children_reset";
stream_child_input(_, "supervisor_admission") -> "domain_admission";
stream_child_input(I, "supervisor_valid") -> "control_" ++ prefix(I) ++ "management_valid";
stream_child_input(I, "supervisor_op") -> "control_" ++ prefix(I) ++ "management_op";
stream_child_input(I, "supervisor_fault") -> "control_" ++ prefix(I) ++ "management_fault";
stream_child_input(I, "supervisor_expected") -> "control_" ++ prefix(I) ++ "expected";
stream_child_input(I, "supervisor_target") -> "control_" ++ prefix(I) ++ "target";
stream_child_input(I, "supervisor_transition") -> "control_" ++ prefix(I) ++ "transition";
stream_child_input(I, Name) -> prefix(I) ++ Name.
