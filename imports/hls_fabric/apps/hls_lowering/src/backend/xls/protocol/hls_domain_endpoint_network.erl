-module(hls_domain_endpoint_network).
-moduledoc "Connects one local domain/endpoint role to its packet router and endpoint management parser. This is wiring between emitted interfaces: no application scheduling, packet storage or peer lifecycle is added. Board composition supplies the atomic carrier, host streams and cold reset. Physical carrier/router faults reach the domain lifecycle; host parser/session faults remain connection-level observations.".

%% Pure composition of already emitted units.
-export([emit/3]).
-export_type([result/0]).

%% All widths come from the corresponding emitted child interface.
-type ports() :: [{string(), pos_integer()}].
%% Child builders retain additional typed metadata; composition consumes only these three fields.
-type unit() :: #{top_module := string(), inputs := ports(), outputs := ports(), atom() => term()}.

-doc "Public local-domain, management and atomic-carrier pins, with all raw endpoint pins private. Child dependencies are supplied separately. Internal unused diagnostic wires may be pruned by synthesis; they are not fabricated observations.".
-type result() :: #{
    top_module := string(),
    inputs := ports(),
    outputs := ports(),
    source := string(),
    domain_index := non_neg_integer(),
    children := #{role := string(), packets := string(), management := string()}
}.

-doc "Wires exact endpoint command and packet pins and remaps management observed_* pins to native endpoint outputs. Rejects identity, width, direction and duplicate-driver mismatches. The only shared input is cold reset; transport-session resets remain independent parser inputs. Carrier and retained router faults drive the native domain failure input without resetting its incarnation history. Host endpoint_wire_fault stays a separate connection-level observation.".
-spec emit(
    hls_domain_endpoint_role:result(),
    hls_domain_endpoint_packets:result(),
    hls_domain_endpoints_stream:result()
) -> hls_generated_files:output(result()).
emit(
    Role = #{domain_index := Index, endpoints := Endpoints},
    Packets = #{routes := Routes},
    Management = #{interface := #{endpoints := Managed}}
) ->
    Expected = identities(Endpoints),
    require(Expected =:= identities(Routes), packet_endpoints),
    require(Expected =:= identities(Managed), management_endpoints),
    Units = [{role, Role}, {packets, Packets}, {management, Management}],
    lists:foreach(fun({_Kind, Unit}) -> validate(Unit) end, Units),
    FabricFault = "domain_" ++ integer_to_list(Index) ++ "_fabric_fault",
    require(lists:member({FabricFault, 1}, maps:get(inputs, Role)), domain_fabric_fault),
    RoleInputs = internal(maps:get(inputs, Role)),
    RoleOutputs = internal(maps:get(outputs, Role)),
    Commands = internal(maps:get(outputs, Packets)) ++ internal(maps:get(outputs, Management)),
    require(lists:sort(RoleInputs) =:= lists:sort(Commands), endpoint_drivers),
    Consumers = [
        {wire_name(Kind, Name), Width}
     || {Kind, Unit} <- tl(Units),
        {Name, Width} <- internal(maps:get(inputs, Unit))
    ],
    lists:foreach(
        fun(Pin) -> require(lists:member(Pin, RoleOutputs), {endpoint_observation, Pin}) end,
        Consumers
    ),
    Inputs =
        [{"reset", 1}] ++
            lists:keydelete(
                FabricFault,
                1,
                lists:append([external(maps:get(inputs, Unit), true) || {_, Unit} <- Units])
            ),
    require(lists:member({"carrier_fault", 1}, Inputs), carrier_fault),
    require(lists:member({"router_fault", 1}, maps:get(outputs, Packets)), router_fault),
    Outputs = lists:append([external(maps:get(outputs, Unit), false) || {_, Unit} <- Units]),
    Top = "endpoint_network_" ++ integer_to_list(Index),
    validate(#{top_module => Top, inputs => Inputs, outputs => Outputs}),
    Text = [
        "// Domain, endpoint packet router and metadata-only management; no added state.\n",
        "module ",
        Top,
        "(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [wire(P) || P <- [{FabricFault, 1} | RoleInputs ++ RoleOutputs]],
        "assign ",
        FabricFault,
        " = carrier_fault || router_fault;\n",
        [instance(Kind, Unit) || {Kind, Unit} <- Units],
        "endmodule\n"
    ],
    Source = Top ++ ".sv",
    #{
        files => #{Source => Text},
        result => #{
            top_module => Top,
            inputs => Inputs,
            outputs => Outputs,
            source => Source,
            domain_index => Index,
            children => maps:from_list([{Kind, maps:get(top_module, Unit)} || {Kind, Unit} <- Units])
        }
    }.

%% Source crossing IDs and directions must match in all three independently emitted components.
-spec identities([#{id := non_neg_integer(), kind := tx | rx, atom() => term()}]) ->
    [{non_neg_integer(), tx | rx}].
identities(Endpoints) ->
    Values = [{Id, Kind} || #{id := Id, kind := Kind} <- Endpoints],
    require(length(Values) =:= length(Endpoints), endpoint_identity),
    require(length(Values) =:= length(lists:usort([Id || {Id, _} <- Values])), duplicate_endpoint),
    lists:sort(Values).

%% Only endpoint_NUMERICID_* pins are private; endpoint_management_* remains public.
-spec endpoint_pin(string()) -> boolean().
endpoint_pin(Name) -> re:run(Name, "^endpoint_[0-9]+_", [{capture, none}]) =:= match.

%% Filter complete typed pins rather than reconstructing their widths or names.
-spec internal(ports()) -> ports().
internal(Ports) -> [P || P = {Name, _} <- Ports, endpoint_pin(Name)].

%% One cold reset clocks all children; every other non-endpoint pin keeps its emitted name.
-spec external(ports(), boolean()) -> ports().
external(Ports, RemoveReset) ->
    [
        P
     || P = {Name, _} <- Ports, not endpoint_pin(Name), not (RemoveReset andalso Name =:= "reset")
    ].

%% Management names distinguish observations from commands; both refer to the same native output wire.
-spec wire_name(role | packets | management, string()) -> string().
wire_name(management, Name) ->
    case re:run(Name, "^(endpoint_[0-9]+_)observed_(.*)$", [{capture, [1, 2], list}]) of
        {match, [Prefix, Field]} -> Prefix ++ Field;
        nomatch -> Name
    end;
wire_name(_, Name) ->
    Name.

%% Check legal unique ports before generating instances or exposing a combined interface.
-spec validate(unit()) -> ok.
validate(#{top_module := Module, inputs := Inputs, outputs := Outputs}) ->
    Names = [Name || {Name, _} <- Inputs ++ Outputs],
    lists:foreach(fun identifier/1, [Module | Names]),
    require(not lists:member("clk", Names), reserved_clock),
    require(length(Names) =:= length(lists:usort(Names)), duplicate_pin),
    require(lists:member({"reset", 1}, Inputs), cold_reset),
    require(lists:all(fun({_, Width}) -> Width > 0 end, Inputs ++ Outputs), pin_width).

%% Reject path fragments and HDL syntax in names supplied through retained metadata.
-spec identifier(string()) -> ok.
identifier(Name) ->
    require(
        re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]) =:= match,
        {identifier, Name}
    ).

%% Instances preserve emitted port order for readable correspondence with each child.
-spec instance(role | packets | management, unit()) -> iodata().
instance(Kind, #{top_module := Module, inputs := Inputs, outputs := Outputs}) ->
    [
        Module,
        " ",
        atom_to_list(Kind),
        "_unit(.clk(clk),\n",
        lists:join(",\n", [
            [".", Name, "(", wire_name(Kind, Name), ")"]
         || {Name, _} <- Inputs ++ Outputs
        ]),
        "\n);\n"
    ].

%% Scalar declarations omit a redundant range.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port(Direction, {Name, Width}) -> [Direction, " wire ", range(Width), Name].

%% Every private wire has exactly one checked producer, even if a diagnostic has no consumer.
-spec wire({string(), pos_integer()}) -> iodata().
wire({Name, Width}) -> ["wire ", range(Width), Name, ";\n"].

%% HDL vector bounds follow the emitted source width.
-spec range(pos_integer()) -> iodata().
range(1) -> "";
range(Width) -> ["[", integer_to_list(Width - 1), ":0] "].

%% Composition failures identify the mismatched contract before any RTL compiler is invoked.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> erlang:error({endpoint_network, Reason}).
