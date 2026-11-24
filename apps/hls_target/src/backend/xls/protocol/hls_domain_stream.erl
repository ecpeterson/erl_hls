-module(hls_domain_stream).
-moduledoc "Binds source-domain actor schemas to a reusable framed hardware endpoint. hls_protocol_domain writes this composition; hls_domain_fabric consumes its retained interface without compiler access. Separate management and application lanes keep lifecycle observations independent of incomplete application frames.".

%% Source binding and emitted stream composition.
-export([bind/1, emit/1, emit_supervised/1, emit_partition/1, ports/0, supervised_ports/1]).
-export_type([plan/0, result/0]).

%% A source-checked rectangle address selects exactly one physical actor.
-type address() :: #{
    target := 0..3,
    x := hls_nums:u16(),
    y := hls_nums:u16(),
    rectangle => {pos_integer(), pos_integer()}
}.
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
        inputs := [{string(), pos_integer()}],
        outputs := [{string(), pos_integer()}],
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

-doc "Derives addressed actor schemas, call slots and external stream identities from one checked transport descriptor. Each point address must identify exactly one actor. A rectangle may select multiple actors when all members implement the tag as a cast. Ambiguous point addresses and indistinguishable external outputs reject.".
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
            Contract = service_contract(Spec),
            Retained = maps:get(retained_calls, Spec, none),
            Count =
                case Retained of
                    none -> 0;
                    #{mode := immediate, calls := Calls} when map_size(Calls) =:= 0 -> 0;
                    %% Wire routing retains one caller until its same-callback reply arrives.
                    #{mode := immediate} -> 1;
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
        [Actor || Actor = #{id := Id} <- Actors, maps:is_key(Id, Indexed)]
    ),
    ByIndex = maps:from_list([{maps:get(index, B), B} || {_, B} <- Bindings]),
    RectangleCasts = rectangle_casts(Ingress, ByIndex),
    Addressed = maps:from_list([
        {Id, B#{
            ingress := maps:map(
                fun(Tag, A = #{target := T}) ->
                    case maps:find({T, Tag}, RectangleCasts) of
                        {ok, Shape} -> A#{rectangle => Shape};
                        error -> A
                    end
                end,
                maps:get(ingress, B)
            )
        }}
     || {Id, B} <- Bindings
    ]),
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
        actors => Addressed,
        call_slots => max(1, Slots),
        streams => Outputs,
        management_route => {0, 0},
        application_route => {0, 1}
    }.

%% A multicast cannot allocate reply slots. Every recipient on the declared target must
%% implement the tag as a cast, including actors on the far edge of the rectangle.
-spec rectangle_casts(hls_protocol_control:plan(), #{non_neg_integer() => actor()}) ->
    #{{non_neg_integer(), atom()} => {pos_integer(), pos_integer()}}.
rectangle_casts(#{targets := Targets, width := W, height := H}, Actors) ->
    maps:from_list([
        {{T, Tag}, {W, H}}
     || #{selector := T, schemas := Tags, recipients := Rs} <- Targets,
        Rs =/= [],
        Tag <- Tags,
        lists:all(
            fun(#{index := I}) ->
                case maps:find(I, Actors) of
                    {ok, #{contract := #{casts := Casts, calls := Calls}, schemas := Schemas}} ->
                        #{width := Bits} = maps:get(Tag, Schemas),
                        (Bits + 31) div 32 + 11 =< 255 andalso
                            lists:member(Tag, Casts) andalso not maps:is_key(Tag, Calls);
                    error ->
                        false
                end
            end,
            Rs
        )
    ]).

%% The retained program owns request kinds; cast-only actors need no artificial caller slots.
-spec service_contract(xls_actor_codegen:spec()) -> hls_service_schema:contract().
service_contract(#{retained_calls := none, casts := Casts}) ->
    #{calls => #{}, casts => lists:usort([Tag || #{tag := Tag} <- Casts])};
service_contract(#{retained_calls := Contract}) ->
    maps:with([calls, casts, pending_calls, continuations], Contract).

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

-doc "Emits the framed top around the checked raw domain. Per-call request storage is bounded by declared pending_calls; each stream retains at most one packet. Optional process inspection remains on dedicated inspect_address/inspect_incarnation/app_inspect_value pins, independent of session packet lanes. No live-device timing or safety guarantee is inferred.".
-spec emit(hls_protocol_domain:result()) -> result().
emit(Result) -> emit_mode(Result, false, false).

-doc "Emits the same bounded stream with supervisor-owned lifecycle pins. Host commands can only watch one ready incarnation or acknowledge its retained retirement receipt; they cannot reset a child. A fresh transport session discards observer evidence, never actor state. Process inspection rejects until its queries are bound to the parent lifetime.".
-spec emit_supervised(hls_protocol_domain:result()) -> result().
emit_supervised(Result = #{network := #{inspection := none}}) ->
    emit_mode(Result, true, false);
emit_supervised(_) ->
    hls_diagnostic:raise(
        domain,
        supervised_inspection_unavailable,
        <<"Supervised process inspection requires a parent-bound query interface.">>,
        #{path => [inspection], value => process}
    ).

-doc "Emits host-managed framing for a checked partition while carrying its raw crossings and lifecycle observations to an enclosing incarnation-bound owner. fabric_fault reports failure of that crossing fabric through the native lifecycle; it neither resets the core nor disconnects host management. Crossings run independently of host session/framing stalls. domain_reset resets only the core, preserving accepted host-output evidence; reset remains the global cold boundary.".
-spec emit_partition(hls_protocol_domain:result()) -> result().
emit_partition(Result) -> emit_mode(Result, false, true).

%% The stream mode changes authority and observation shape, not application framing.
-spec emit_mode(hls_protocol_domain:result(), boolean(), boolean()) -> result().
emit_mode(
    Result = #{frame_payload_words := Words, codecs := Codecs, stream := Stream},
    Supervised,
    Partition
) ->
    {CrossInputs, CrossOutputs} = crossing_ports(Result, Partition),
    {InspectInputs, InspectOutputs} = inspection_ports(Result),
    SideInputs = CrossInputs ++ InspectInputs,
    SideOutputs = CrossOutputs ++ InspectOutputs,
    #{actors := Actors, call_slots := Slots, streams := Outputs} = Stream,
    %% Preserve the point/reply capacity even when a full-size record cannot fit
    %% two more coordinate words. Grow the buffer only for eligible multicast tags.
    RectangleWords = [
        11 + (Bits + 31) div 32
     || #{ingress := Ingress, schemas := Schemas} <- maps:values(Actors),
        {Tag, #{rectangle := _}} <- maps:to_list(Ingress),
        #{width := Bits} <- [maps:get(Tag, Schemas)]
    ],
    PacketWords = max(
        case Supervised of
            true -> 28;
            false -> 18
        end,
        lists:max([10 + Words | RectangleWords])
    ),
    true = PacketWords =< 255,
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_target), "xls/templates/domain_stream.x.in")
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
                {<<"@@EXTERNAL_CONTROL@@">>, external_control(Supervised, Partition)},
                {<<"@@CROSSING_INPUTS@@">>, struct_fields(SideInputs)},
                {<<"@@CROSSING_OUTPUTS@@">>, struct_fields(SideOutputs)},
                {<<"@@FABRIC_FAULT@@">>,
                    case Partition of
                        true -> "io.fabric_fault";
                        false -> "false"
                    end},
                {<<"@@CROSSING_CONTROL@@">>, [
                    [N, ": io.", N, ",\n"]
                 || {N, _} <- SideInputs, not lists:member(N, ["domain_reset", "fabric_fault"])
                ]},
                {<<"@@CROSSING_OBSERVATIONS@@">>, [
                    [N, ": core.output.", N, ",\n"]
                 || {N, _} <- SideOutputs
                ]},
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
    {BaseInputs, BaseOutputs} =
        case Supervised of
            true -> supervised_ports(Codecs);
            false -> ports()
        end,
    Inputs = BaseInputs ++ SideInputs,
    Pins = BaseOutputs ++ SideOutputs,
    #{
        inputs => Inputs,
        outputs => Pins,
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
                        " && ",
                        command_kind(Kind, Address),
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
                        %% Casts carry sentinel 255 on the wire but own no call slot.
                        case IsCall of
                            true -> [n(Base), "+slot"];
                            false -> "0"
                        end,
                        ",target:u2:",
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

%% Only cast-compatible groups accept extended bounds; point packets retain their ABI.
-spec command_kind(0 | 1, address()) -> iodata().
command_kind(0, #{rectangle := {W, H}}) ->
    [
        "(kind == u32:0 || ((kind == u32:2 || kind == u32:3) && x0 <= x1 && y0 <= y1 && x1 as u32 < u32:",
        n(W),
        " && y1 as u32 < u32:",
        n(H),
        "))"
    ];
command_kind(K, _) ->
    ["kind == u32:", n(K)].

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

%% Only the explicit partition composition exposes these pins; standalone stream ABI is unchanged.
-spec crossing_ports(hls_protocol_domain:result(), boolean()) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
crossing_ports(_, false) ->
    {[], []};
crossing_ports(#{inputs := Inputs, outputs := Outputs}, true) ->
    {
        [
            {"domain_reset", 1},
            {"fabric_fault", 1}
            | [P || P = {N, _} <- Inputs, lists:prefix("remote_", N)]
        ],
        [
            P
         || P = {N, _} <- Outputs,
            lists:prefix("app_remote_", N) orelse
                N =:= "domain_phase" orelse N =:= "domain_current"
        ]
    }.

%% Inspection uses the raw domain's epoch gate and contributes no packet or actor storage.
-spec inspection_ports(hls_protocol_domain:result()) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
inspection_ports(#{network := #{inspection := none}}) ->
    {[], []};
inspection_ports(#{inputs := Inputs, outputs := Outputs}) ->
    true = lists:member({"inspect_address", 32}, Inputs),
    true = lists:member({"inspect_incarnation", 64}, Inputs),
    true = lists:member({"app_inspect_value", 128}, Outputs),
    {[{"inspect_address", 32}, {"inspect_incarnation", 64}], [{"app_inspect_value", 128}]}.

%% Supervisor observations have no application payload or shared transport buffer.
-spec external_outputs(boolean(), hls_protocol_domain:codecs()) -> iodata().
external_outputs(false, _) -> [];
external_outputs(true, Codecs) -> struct_fields(supervisor_outputs(Codecs)).

%% One authority supplies management; the unselected source is absent after constant folding.
-spec external_control(boolean(), boolean()) -> iodata().
external_control(false, false) ->
    "let core_reset = io.reset; let parent_admission = true;";
external_control(false, true) ->
    "let core_reset = io.reset || io.domain_reset; let parent_admission = true;";
external_control(true, false) ->
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
