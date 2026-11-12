-module(hls_domain_stream).
-moduledoc "Binds source-domain actor schemas to a reusable framed hardware endpoint. hls_protocol_domain writes this composition; hls_domain_fabric consumes its retained interface without compiler access. Separate management and application lanes keep lifecycle observations independent of incomplete application frames.".

%% Source binding and emitted stream composition.
-export([bind/1, emit/1, emit_supervised/1, ports/0, supervised_ports/1]).
-export_type([plan/0, result/0]).

%% A source-checked rectangle address selects exactly one physical actor.
-type address() :: #{target := 0..3, x := hls_nums:u16(), y := hls_nums:u16()}.
%% Retained runtime schema plus statically allocated caller storage and ingress wiring.
-type actor() :: #{
    index := hls_nums:u32(),
    schemas := hls_host_codec:catalog(),
    contract := hls_service_schema:contract(),
    outputs := #{atom() => [atom()]},
    ports := #{atom() => hls_nums:u32()},
    reply_port := none | atom(),
    slot_base := non_neg_integer(),
    pending_calls := non_neg_integer(),
    ingress := #{atom() => address()}
}.
%% Each external source/recipient stream has one unambiguous source port.
-type stream() :: #{
    actor := hls_nums:u32(),
    port := hls_nums:u32(),
    reply := boolean(),
    base := non_neg_integer(),
    count := non_neg_integer(),
    name := string()
}.
-doc "Source-derived actor addresses, caller storage and external output wiring for the framed domain endpoint.".
-type plan() :: #{
    actors := #{term() => actor()},
    call_slots := pos_integer(),
    streams := [stream()],
    management_route := {0, 0},
    application_route := {0, 1}
}.

-doc "Emitted files, bounded transport storage, lifecycle authority and deployment session pins.".
-type result() ::
    #{
        files := #{string() => iodata()},
        state_bit_budget := pos_integer(),
        packet_words := pos_integer(),
        supervision := host | local,
        session := #{
            bits := 64,
            establishment := out_of_band,
            ordering := strictly_increasing,
            prefix_words := 2,
            input := string(),
            reset := string(),
            observed := string(),
            attached := string(),
            preserves := [actor_state | incarnation]
        }
    }.

-doc "Derives addressed actor schemas, call slots and external stream identities from one checked transport descriptor. Each framed command must select exactly one actor; ambiguous rectangle points and external outputs shared by indistinguishable source ports reject.".
-spec bind(hls_protocol_transport:descriptor()) -> plan().
bind(#{
    bundle := #{topology := #{actors := Actors}, modules := Modules},
    fabric := #{sources := Sources, boundaries := Boundaries},
    ingress := Ingress
}) ->
    Indexed = maps:from_list([{Id, I} || #{actor := Id, index := I} <- Sources]),
    {Bindings, Slots} = lists:mapfoldl(
        fun(#{id := Id, module := Module}, Base) ->
            Interface = hls_actor_interface:from_module(Module),
            #{program := Program} = maps:get(Module, Modules),
            Spec = xls_actor_program:spec(Program),
            Names = maps:get(output_names, Spec),
            Ports = maps:from_list(lists:zip(Names, lists:seq(0, length(Names) - 1))),
            {ok, Contract} = hls_service_schema:from_module(Module),
            Retained = maps:get(retained_calls, Spec, none),
            Count =
                case Retained of
                    none -> 0;
                    #{pending_calls := N} -> N
                end,
            Index = maps:get(Id, Indexed),
            {
                {Id, #{
                    index => Index,
                    schemas => hls_host_codec_plan:schemas(Interface),
                    contract => Contract,
                    outputs => hls_host_codec_plan:outputs(Interface),
                    ports => Ports,
                    reply_port =>
                        case Retained of
                            none -> none;
                            #{port := P} -> P
                        end,
                    slot_base => Base,
                    pending_calls => Count,
                    ingress => ingress(Index, Ingress)
                }},
                Base + Count
            }
        end,
        0,
        Actors
    ),
    ByIndex = maps:from_list([{maps:get(index, B), B} || {_, B} <- Bindings]),
    Outputs = [
        begin
            Binding = maps:get(I, ByIndex),
            [Port] = lists:usort([P || #{port := P} <- Rows]),
            #{
                actor => I,
                port => maps:get(Port, maps:get(ports, Binding)),
                reply => Port =:= maps:get(reply_port, Binding),
                base => maps:get(slot_base, Binding),
                count => maps:get(pending_calls, Binding),
                name => "boundary_" ++ integer_to_list(I) ++ "_" ++ integer_to_list(D)
            }
        end
     || #{source_index := I, output := #{index := D, rows := Rows}} <- Boundaries
    ],
    #{
        actors => maps:from_list(Bindings),
        call_slots => max(1, Slots),
        streams => Outputs,
        management_route => {0, 0},
        application_route => {0, 1}
    }.

%% Every retained command address selects one actor, even when other targets broadcast.
-spec ingress(non_neg_integer(), hls_protocol_control:plan()) -> #{atom() => address()}.
ingress(Index, #{targets := Targets}) ->
    lists:foldl(
        fun(#{selector := Target, schemas := Schemas, recipients := Recipients}, Found) ->
            lists:foldl(
                fun
                    (#{index := I, x := X, y := Y}, Acc) when I =:= Index ->
                        Same = [R || R = #{x := RX, y := RY} <- Recipients, RX =:= X, RY =:= Y],
                        case length(Same) of
                            1 ->
                                lists:foldl(
                                    fun(Tag, A) ->
                                        case maps:is_key(Tag, A) of
                                            true -> A;
                                            false -> A#{Tag => #{target => Target, x => X, y => Y}}
                                        end
                                    end,
                                    Acc,
                                    Schemas
                                );
                            _ ->
                                Acc
                        end;
                    (_, Acc) ->
                        Acc
                end,
                Found,
                Recipients
            )
        end,
        #{},
        Targets
    ).

-doc "Emits the framed top around the checked raw domain. Per-call request storage is bounded by declared pending_calls; each stream retains at most one packet. No live-device timing or safety guarantee is inferred.".
-spec emit(hls_protocol_domain:result()) -> result().
emit(Result) -> emit_mode(Result, false).

-doc "Emits the same bounded stream with supervisor-owned lifecycle pins. Host commands can only watch one ready incarnation or acknowledge its retained retirement receipt; they cannot reset a child. A fresh transport session discards observer evidence, never actor state.".
-spec emit_supervised(hls_protocol_domain:result()) -> result().
emit_supervised(Result) -> emit_mode(Result, true).

%% The stream mode changes authority and observation shape, not application framing.
-spec emit_mode(hls_protocol_domain:result(), boolean()) -> result().
emit_mode(#{frame_payload_words := Words, codecs := Codecs, stream := Stream}, Supervised) ->
    #{actors := Actors, call_slots := Slots, streams := Outputs} = Stream,
    PacketWords = max(
        case Supervised of
            true -> 28;
            false -> 18
        end,
        10 + Words
    ),
    true = PacketWords =< 255,
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_lowering), "xls/templates/domain_stream.x.in")
    ),
    Widths = [
        {
            <<"@@", (string:uppercase(atom_to_binary(K)))/binary, "_BITS@@">>,
            integer_to_binary(hls_type:width(maps:get(K, Codecs)))
        }
     || K <- [operation, status, action, fault]
    ],
    Text = xls_template:render(
        Template,
        Widths ++
            [
                {<<"@@PACKET_BITS@@">>, integer_to_binary(PacketWords * 32)},
                {<<"@@SUPERVISED@@">>, atom_to_list(Supervised)},
                {<<"@@EXTERNAL_INPUTS@@">>, external_inputs(Supervised, Codecs)},
                {<<"@@EXTERNAL_OUTPUTS@@">>, external_outputs(Supervised, Codecs)},
                {<<"@@EXTERNAL_CONTROL@@">>, external_control(Supervised)},
                {<<"@@MANAGEMENT_CONTROL@@">>, management_control(Supervised)},
                {<<"@@EXTERNAL_OBSERVATIONS@@">>, external_observations(Supervised)},
                {<<"@@SLOTS@@">>, integer_to_binary(Slots)},
                {<<"@@OUTPUTS@@">>, integer_to_binary(length(Outputs))},
                {<<"@@COMMANDS@@">>, commands(Actors)},
                {<<"@@OUTPUT_SELECT@@">>, output_select(Outputs)},
                {<<"@@OUTPUT_READY@@">>, [
                    [
                        maps:get(name, O),
                        "_ready: granted && grant == u32:",
                        integer_to_list(K),
                        ",\n"
                    ]
                 || {K, O} <- lists:enumerate(0, Outputs)
                ]}
            ]
    ),
    {Inputs, Pins} =
        case Supervised of
            true -> supervised_ports(Codecs);
            false -> ports()
        end,
    #{
        files => #{
            "domain/domain_stream.x" => Text,
            "domain/domain_stream.sv" => sv_protocol_ports:emit(
                Inputs, Pins, "domain_stream", "domain_stream_core"
            )
        },
        state_bit_budget => 4 * (PacketWords + 2) * 32 + Slots * 34 + 512 + 65 +
            512,
        supervision =>
            case Supervised of
                true -> local;
                false -> host
            end,
        packet_words => PacketWords,
        session => #{
            bits => 64,
            establishment => out_of_band,
            ordering => strictly_increasing,
            prefix_words => 2,
            input => "transport_session",
            reset => "transport_reset",
            observed => "transport_session_observed",
            attached => "transport_attached",
            preserves => [actor_state, incarnation]
        }
    }.

%% Runtime records keep their ordinary source selectors and canonical payload lengths.
-spec commands(#{term() => actor()}) -> iodata().
commands(Actors) ->
    Cases = lists:append([
        begin
            #{
                index := I,
                schemas := Schemas,
                contract := Contract,
                ingress := Ingress,
                slot_base := Base,
                pending_calls := Count
            } = A,
            Calls = maps:get(calls, Contract),
            Casts = maps:get(casts, Contract),
            [
                begin
                    #{selector := Selector, width := Width} = maps:get(Tag, Schemas),
                    IsCall = maps:is_key(Tag, Calls),
                    Kind =
                        case IsCall of
                            true -> 1;
                            false -> 0
                        end,
                    true = IsCall orelse lists:member(Tag, Casts),
                    #{target := Target, x := X, y := Y} = Address,
                    [
                        "if actor == u32:",
                        n(I),
                        " && tag == u8:",
                        n(Selector),
                        " && kind == u32:",
                        n(Kind),
                        " && words == u8:",
                        n((Width + 31) div 32),
                        " && slot ",
                        case IsCall of
                            true -> ["< u32:", n(Count)];
                            false -> "== u32:255"
                        end,
                        " { Command {valid:true,call:",
                        atom_to_list(IsCall),
                        ",slot:u32:",
                        n(Base),
                        "+slot,target:u2:",
                        n(Target),
                        ",x:u16:",
                        n(X),
                        ",y:u16:",
                        n(Y),
                        "} } else "
                    ]
                end
             || {Tag, Address} <- lists:sort(maps:to_list(Ingress))
            ]
        end
     || {_, A} <- lists:sort(maps:to_list(Actors))
    ]),
    [Cases, "{zero!<Command>()}"].

%% Payload selection follows a work-conserving grant over source availability bits.
-spec output_select([stream()]) -> iodata().
output_select(Outputs) ->
    [
        "match index {\n",
        [
            [
                "u32:",
                n(K),
                " => Output {valid:observation.app_",
                Name,
                "_valid, actor:u32:",
                n(I),
                ",port:u32:",
                n(Port),
                ",reply:",
                atom_to_list(Reply),
                ",base:u32:",
                n(Base),
                ",count:u32:",
                n(Count),
                ",frame:axis::frame_from_bits(observation.app_",
                Name,
                "_data)},\n"
            ]
         || {K, #{
                name := Name, actor := I, port := Port, reply := Reply, base := Base, count := Count
            }} <- lists:enumerate(0, Outputs)
        ],
        "_ => zero!<Output>(),}"
    ].

-doc "Named sampled pin buses for two independent word streams and an out-of-band session boundary. transport_session_observed is the hardware acknowledgement; reset alone is the cold domain reset.".
-spec ports() -> {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
ports() ->
    {
        [{"reset", 1}, {"transport_reset", 1}, {"transport_session", 64}] ++
            lists:append([
                [
                    {P ++ "_word", 32},
                    {P ++ "_valid", 1},
                    {P ++ "_last", 1},
                    {P ++ "_output_ready", 1}
                ]
             || P <- ["management", "application"]
            ]),
        lists:append([
            [
                {P ++ "_ready", 1},
                {P ++ "_output_word", 32},
                {P ++ "_output_valid", 1},
                {P ++ "_output_last", 1}
            ]
         || P <- ["management", "application"]
        ]) ++ [{"wire_fault", 1}, {"transport_session_observed", 64}, {"transport_attached", 1}]
    }.

%% Decimal text is used only at statically elaborated wiring boundaries.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).

-doc "Adds private supervisor commands and lifecycle observations to the ordinary stream pins. reset is cold reset; supervisor_reset resets only the enclosed domain, preserving accepted packet/frontier evidence.".
-spec supervised_ports(hls_protocol_domain:codecs()) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
supervised_ports(Codecs) ->
    {Inputs, Outputs} = ports(),
    {Inputs ++ supervisor_inputs(Codecs), Outputs ++ supervisor_outputs(Codecs)}.

%% Private pins are driven only by the compiled parent, never by host packets.
-spec supervisor_inputs(hls_protocol_domain:codecs()) -> [{string(), pos_integer()}].
supervisor_inputs(Codecs) ->
    [
        {"supervisor_reset", 1},
        {"supervisor_admission", 1},
        {"supervisor_valid", 1},
        {"supervisor_op", hls_type:width(maps:get(operation, Codecs))},
        {"supervisor_expected", 64},
        {"supervisor_target", 64},
        {"supervisor_transition", 64},
        {"supervisor_fault", hls_type:width(maps:get(fault, Codecs))}
    ].

%% The same raw lifecycle snapshots drive local recovery independently of host observation.
-spec supervisor_outputs(hls_protocol_domain:codecs()) -> [{string(), pos_integer()}].
supervisor_outputs(Codecs) ->
    [
        {"domain_phase", hls_type:width(maps:get(phase, Codecs))},
        {"domain_current", 64},
        {"domain_previous", 64},
        {"domain_target", 64},
        {"domain_transition", 64},
        {"domain_fault", hls_type:width(maps:get(fault, Codecs))},
        {"domain_reusable", 1}
    ].

%% Empty fields keep the existing standalone public pin ABI unchanged.
-spec external_inputs(boolean(), hls_protocol_domain:codecs()) -> iodata().
external_inputs(false, _) -> [];
external_inputs(true, Codecs) -> struct_fields(supervisor_inputs(Codecs)).

%% Supervisor observations have no application payload or shared transport buffer.
-spec external_outputs(boolean(), hls_protocol_domain:codecs()) -> iodata().
external_outputs(false, _) -> [];
external_outputs(true, Codecs) -> struct_fields(supervisor_outputs(Codecs)).

%% One authority supplies management; the unselected source is absent after constant folding.
-spec external_control(boolean()) -> iodata().
external_control(false) ->
    "let core_reset = io.reset; let parent_admission = true;";
external_control(true) ->
    "let core_reset = io.reset || io.supervisor_reset; let parent_admission = io.supervisor_admission;".

%% Lifecycle observations and transport retirement clearance feed the parent's bounded scanner.
-spec external_observations(boolean()) -> iodata().
external_observations(false) ->
    [];
external_observations(true) ->
    [
        "domain_reusable: s.watched == u64:0 && !s.retirement.valid && !s.application_tx_valid,\n",
        [
            [N, ": core.output.", N, ",\n"]
         || N <- [
                "domain_phase",
                "domain_current",
                "domain_previous",
                "domain_target",
                "domain_transition",
                "domain_fault"
            ]
        ]
    ].

%% Struct order is the sampled hardware interface order.
-spec struct_fields([{string(), pos_integer()}]) -> iodata().
struct_fields(Fields) -> [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields].

%% Management of a supervised child is exclusively local; the stream accepts only observer commands.
-spec management_control(boolean()) -> iodata().
management_control(false) ->
    [
        "management_valid: management_valid && management_request,\n",
        "management_op: word(management,u32:1) as Operation,\n",
        "expected: pair(management,u32:2), target: pair(management,u32:4),\n",
        "transition: pair(management,u32:6),\n",
        "management_fault: word(management,u32:8) as Fault,"
    ];
management_control(true) ->
    [
        "management_valid: io.supervisor_valid, management_op: io.supervisor_op,\n",
        "expected: io.supervisor_expected, target: io.supervisor_target,\n",
        "transition: io.supervisor_transition, management_fault: io.supervisor_fault,"
    ].
