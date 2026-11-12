-module(sv_domain_channels).
-moduledoc "Stateless wiring for separate source domains and incarnation-bound mailbox channels. hls_protocol_domains owns placement and restart-group checks; source-generated domain and channel cores own every state transition. Host lifecycle/effect pins and bounded channel transport pins remain public.".

%% Checked composite pin layout and mechanical RTL.
-export([ports/3, emit/3]).

%% Field order is the sampled pin order retained by each independent generated unit.
-type ports() :: [{string(), pos_integer()}].
%% The shared channel builder supplies its own exact widths and codec descriptors.
-type channel() :: hls_domain_channel_build:result().

-doc "Returns global cold reset, namespaced per-domain pins and namespaced per-crossing transport/control pins. Raw crossing actor pins are private. Independent domain reset never resets channel ownership; global reset requires deployment exclusion of old traffic.".
-spec ports([hls_protocol_domains:domain()], [hls_protocol_domains:crossing()], channel()) ->
    {ports(), ports()}.
ports(Domains, Crossings, #{inputs := ChannelInputs, outputs := ChannelOutputs}) ->
    Inputs =
        [{"reset", 1}] ++
            lists:append([
                [{domain(Index) ++ N, W} || {N, W} <- Ps, not remote_input(N)]
             || #{index := Index, interface := #{inputs := Ps}} <- Domains
            ]) ++
            lists:append([
                [{channel(Index) ++ N, W} || {N, W} <- ChannelInputs, not private_input(N)]
             || #{index := Index} <- Crossings
            ]),
    Outputs =
        lists:append([
            [{domain(Index) ++ N, W} || {N, W} <- Ps, not remote_output(N)]
         || #{index := Index, interface := #{outputs := Ps}} <- Domains
        ]) ++
            lists:append([
                [{channel(Index) ++ N, W} || {N, W} <- ChannelOutputs, not private_output(N)]
             || #{index := Index} <- Crossings
            ]),
    Names = [Name || {Name, _} <- Inputs ++ Outputs],
    true = length(Names) =:= length(lists:usort(Names)),
    {Inputs, Outputs}.

-doc "Renders only module instances, constant comparisons and port connections. Child readiness and current incarnation feed each private channel endpoint; canonical payload/class bits connect unchanged. No application queue, restart decision or frame translation is implemented in Verilog.".
-spec emit([hls_protocol_domains:domain()], [hls_protocol_domains:crossing()], channel()) ->
    iodata().
emit(Domains, Crossings, Channel) ->
    {Inputs, Outputs} = ports(Domains, Crossings, Channel),
    [
        "// Mechanical source-domain/channel composition; ownership policy is compiled Erlang.\n",
        "module protocol_domains(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [domain_instance(D) || D <- Domains],
        [channel_instance(C, Domains, Channel) || C <- Crossings],
        "endmodule\n"
    ].

%% Crossing ports are compiler-controlled names, never application-provided module fragments.
-spec remote_input(string()) -> boolean().
remote_input(Name) -> lists:prefix("remote_", Name).

%% Domain outputs prepend app_ to every raw network observation.
-spec remote_output(string()) -> boolean().
remote_output(Name) -> lists:prefix("app_remote_", Name).

%% Both endpoint identities and their actor handshakes remain inaccessible to the transport.
-spec private_input(string()) -> boolean().
private_input(Name) ->
    lists:member(Name, [
        "reset",
        "source_incarnation",
        "destination_incarnation",
        "source_live",
        "destination_live",
        "source_valid",
        "source_slot",
        "source_frame",
        "destination_ready"
    ]).

%% The channel alone drives actor acceptance and destination delivery.
-spec private_output(string()) -> boolean().
private_output(Name) ->
    lists:member(Name, [
        "source_ready", "destination_valid", "destination_slot", "destination_frame"
    ]).

%% Every domain retains its own reset; only explicit global cold reset also reaches the channel.
-spec domain_instance(hls_protocol_domains:domain()) -> iodata().
domain_instance(#{index := Index, interface := #{inputs := Inputs, outputs := Outputs}}) ->
    Prefix = domain(Index),
    [
        [wire({Prefix ++ N, W}) || {N, W} <- Inputs, remote_input(N)],
        [wire({Prefix ++ N, W}) || {N, W} <- Outputs, remote_output(N)],
        "domain_",
        integer_to_list(Index),
        " instance_",
        integer_to_list(Index),
        "(.clk(clk),\n",
        lists:join(
            ",\n",
            [
                connect(
                    N,
                    case N of
                        "reset" -> ["(reset || ", Prefix, "reset)"];
                        _ -> Prefix ++ N
                    end
                )
             || {N, _} <- Inputs
            ] ++ [connect(N, Prefix ++ N) || {N, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% Link identity selects exact source/destination pins; all transport words stay on public pins.
-spec channel_instance(hls_protocol_domains:crossing(), [hls_protocol_domains:domain()], channel()) ->
    iodata().
channel_instance(
    #{index := Link, source_domain := Source, destination_domain := Destination},
    Domains,
    #{inputs := Inputs, outputs := Outputs}
) ->
    [#{interface := #{codecs := Codecs}}] = [D || D = #{index := I} <- Domains, I =:= Source],
    #{phase := Phase} = Codecs,
    Width = hls_type:width(Phase),
    <<Ready:Width>> = hls_type:pack(ready, Phase),
    [
        "domain_channel crossing_",
        integer_to_list(Link),
        "(.clk(clk),\n",
        lists:join(
            ",\n",
            [connect(N, input(N, Link, Source, Destination, Width, Ready)) || {N, _} <- Inputs] ++
                [connect(N, output(N, Link, Source, Destination)) || {N, _} <- Outputs]
        ),
        "\n);\n"
    ].

%% Connections contain no state; the emitted channel validates ownership before these handshakes.
-spec input(
    string(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    pos_integer(),
    non_neg_integer()
) -> iodata().
input("reset", _, _, _, _, _) ->
    "reset";
input("source_incarnation", _, Source, _, _, _) ->
    domain(Source) ++ "domain_current";
input("destination_incarnation", _, _, Destination, _, _) ->
    domain(Destination) ++ "domain_current";
input("source_live", _, Source, _, Width, Ready) ->
    live(Source, Width, Ready);
input("destination_live", _, _, Destination, Width, Ready) ->
    live(Destination, Width, Ready);
input("source_valid", Link, Source, _, _, _) ->
    domain(Source) ++ remote(Link, "valid", output);
input("source_slot", Link, Source, _, _, _) ->
    domain(Source) ++ remote(Link, "slot", output);
input("source_frame", Link, Source, _, _, _) ->
    domain(Source) ++ remote(Link, "frame", output);
input("destination_ready", Link, _, Destination, _, _) ->
    domain(Destination) ++ remote(Link, "ready", output);
input(Name, Link, _, _, _, _) ->
    channel(Link) ++ Name.

%% The source can release its held publication only when the channel takes ownership.
-spec output(string(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> string().
output("source_ready", Link, Source, _) ->
    domain(Source) ++ remote(Link, "ready", input);
output("destination_valid", Link, _, Destination) ->
    domain(Destination) ++ remote(Link, "valid", input);
output("destination_slot", Link, _, Destination) ->
    domain(Destination) ++ remote(Link, "slot", input);
output("destination_frame", Link, _, Destination) ->
    domain(Destination) ++ remote(Link, "frame", input);
output(Name, Link, _, _) ->
    channel(Link) ++ Name.

%% A public lifecycle observation, not host ingress selection, establishes local endpoint liveness.
-spec live(non_neg_integer(), pos_integer(), non_neg_integer()) -> iodata().
live(Index, Width, Ready) ->
    Prefix = domain(Index),
    [
        "(!reset && !",
        Prefix,
        "reset && ",
        Prefix,
        "domain_phase == ",
        integer_to_list(Width),
        "'d",
        integer_to_list(Ready),
        " && ",
        Prefix,
        "domain_current != 64'd0)"
    ].

%% Source indices are fixed by the fresh topology planner.
-spec remote(non_neg_integer(), string(), input | output) -> string().
remote(Index, Suffix, Direction) ->
    case Direction of
        input -> "";
        output -> "app_"
    end ++
        "remote_" ++ integer_to_list(Index) ++ "_" ++ Suffix.

%% Numeric namespaces keep application atoms out of HDL identifiers.
-spec domain(non_neg_integer()) -> string().
domain(Index) -> "domain_" ++ integer_to_list(Index) ++ "_".

%% Each physical crossing owns independent transport and management lanes.
-spec channel(non_neg_integer()) -> string().
channel(Index) -> "ch_" ++ integer_to_list(Index) ++ "_".

%% Scalar declarations preserve ordinary Verilog handshake spelling.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port(Direction, {Name, 1}) -> [Direction, " wire ", Name];
port(Direction, {Name, Width}) -> [Direction, " wire [", integer_to_list(Width - 1), ":0] ", Name].

%% Only private raw crossing pins need new internal wires.
-spec wire({string(), pos_integer()}) -> iodata().
wire({Name, 1}) -> ["wire ", Name, ";\n"];
wire({Name, Width}) -> ["wire [", integer_to_list(Width - 1), ":0] ", Name, ";\n"].

%% Named associations keep connections independent of struct field order.
-spec connect(string(), iodata()) -> iodata().
connect(Name, Value) -> [".", Name, "(", Value, ")"].
