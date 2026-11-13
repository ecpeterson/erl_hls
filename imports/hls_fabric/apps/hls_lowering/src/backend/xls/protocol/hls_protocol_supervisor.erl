-module(hls_protocol_supervisor).
-moduledoc """
Elaborates a static one-for-one supervisor above independently resettable domains.
The ordinary OTP declaration selects restart policy; explicit child bindings supply
hardware networks. Both lifecycle policies are compiled Erlang. This composer owns
only bounded observation selection, a local clock and physical completion wiring.
Raw emission exposes incarnation-tagged child pins. Stream emission connects independently
framed child observers with bounded retirement records and a framed parent control port.
Process inspection is rejected until the parent lifetime is part of its query boundary.
""".

%% Checked source composition and portable tool input.
-export([plan/1, emit/1, emit_stream/1, write/2, write_stream/2]).
-export_type([config/0, plan/0, result/0]).

-doc "Ordinary supervisor callback, optional dormant temporary child templates and exact network bindings. The declared clock rate supplies local restart-window time; deployment must meet it.".
-type config() :: #{
    supervisor := {module(), term()},
    children := #{atom() := hls_source_config:network() | file:filename()},
    clock_hz := 1..((1 bsl 32) - 1),
    templates => [supervisor:child_spec()]
}.
-doc "Checked slot order, initial child count and per-slot restart policy before source lowering. Dormant templates follow the ordinary initial children.".
-type plan() :: #{
    children := [{atom(), hls_source_config:network() | file:filename()}],
    policies := #{atom() := permanent | temporary},
    initial := non_neg_integer(),
    intensity := 0..16,
    period := 1..((1 bsl 32) - 1),
    clock_hz := 1..((1 bsl 32) - 1)
}.
-doc "Named public pins, per-child interfaces, atom codecs and structural storage bounds. Physical timing and deployment exclusion remain unqualified.".
-type result() :: #{
    inputs := [{string(), pos_integer()}],
    outputs := [{string(), pos_integer()}],
    children := [
        #{id := atom(), index := non_neg_integer(), interface := hls_protocol_domain:result()}
    ],
    codecs := #{atom() := hls_type:descriptor()},
    plan := plan(),
    frame_payload_words := hls_frame_layout:words(),
    control_state_bits := pos_integer(),
    parent_stream => map(),
    eligible := false
}.

-doc "Checks one_for_one with one to 65535 compiled domain slots, bounded intensity and positive period/clock rate. Ordinary permanent and temporary children start with the parent; optional temporary templates remain dormant until requested. All starts must be supervised hls_domain_instance starts. Supplied hardware bindings exactly cover both sets and replace only their owner argument.".
-spec plan(config()) -> plan().
plan(#{supervisor := {Module, Args}, children := Bindings, clock_hz := Hz} = Config) ->
    require(
        (maps:keys(Config) -- [children, clock_hz, supervisor, templates]) =:= [], unknown_option
    ),
    Templates = maps:get(templates, Config, []),
    require(is_list(Templates), templates),
    require(is_integer(Hz) andalso Hz > 0 andalso Hz < (1 bsl 32), clock_hz),
    case Module:init(Args) of
        {ok, {Flags, Specs}} when is_map(Flags), is_list(Specs) ->
            require(maps:get(strategy, Flags, one_for_one) =:= one_for_one, strategy),
            require(maps:get(auto_shutdown, Flags, never) =:= never, auto_shutdown),
            require(
                (maps:keys(Flags) -- [strategy, intensity, period, auto_shutdown]) =:= [],
                supervisor_flags
            ),
            Intensity = maps:get(intensity, Flags, 1),
            Period = maps:get(period, Flags, 5),
            require(
                is_integer(Intensity) andalso Intensity >= 0 andalso Intensity =< 16, intensity
            ),
            require(is_integer(Period) andalso Period > 0 andalso Period < (1 bsl 32), period),
            AllSpecs = Specs ++ Templates,
            Ids = [child_id(S) || S <- AllSpecs],
            require(
                lists:all(fun(S) -> maps:get(restart, S, permanent) =:= temporary end, Templates),
                template_policy
            ),
            require(Ids =/= [] andalso length(Ids) < (1 bsl 16), children),
            require(length(Ids) =:= length(lists:usort(Ids)), duplicate_child),
            require(supervisor:check_childspecs(AllSpecs) =:= ok, child_spec),
            require(lists:sort(Ids) =:= lists:sort(maps:keys(Bindings)), child_bindings),
            #{
                children => [{Id, maps:get(Id, Bindings)} || Id <- Ids],
                policies => maps:from_list([
                    {maps:get(id, S), maps:get(restart, S, permanent)}
                 || S <- AllSpecs
                ]),
                initial => length(Specs),
                intensity => Intensity,
                period => Period,
                clock_hz => Hz
            };
        _ ->
            error({supervisor_declaration, init_result})
    end.

%% A hardware child represents one reset-safe domain; arbitrary start effects are not compiled.
-spec child_id(supervisor:child_spec()) -> atom().
child_id(
    #{
        id := Id,
        start :=
            {hls_domain_instance, start_link, [_Owner, Id, #{lifetime := supervised} = Options]}
    } = Spec
) when is_atom(Id) ->
    require(maps:keys(Options) =:= [lifetime], child_options),
    require(lists:member(maps:get(restart, Spec, permanent), [permanent, temporary]), restart),
    require(maps:get(type, Spec, worker) =:= worker, child_type),
    require(maps:get(significant, Spec, false) =:= false, significant_child),
    require(maps:get(shutdown, Spec, 5000) =/= brutal_kill, brutal_kill),
    require(
        (maps:keys(Spec) -- [id, start, restart, type, significant, shutdown, modules]) =:= [],
        child_fields
    ),
    Id;
child_id(_) ->
    error({supervisor_declaration, child_start}).

%% Invalid declarations remain ordinary compile-time errors with the rejected feature named.
-spec require(boolean(), atom()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({supervisor_declaration, Reason}).

-doc "Produces independent domain units, a compiled supervisor controller and stateless wiring. Grants are accepted only for the initializing parent incarnation, above every earlier grant retained by this hardware lifetime. A global reset requires a fresh externally reserved grant; no transport signal implies reset. Child application lanes run independently of the one-slot-per-clock management scan.".
-spec emit(config()) -> hls_generated_files:output(result()).
emit(Config) -> emit_mode(Config, raw).

-doc "Emits independent framed child observers and parent management/grant framing. Local FPGA policy retains exclusive child lifecycle authority; host watch/acknowledgement controls publication and completion of temporary-slot retirement, without acquiring child lifecycle authority.".
-spec emit_stream(config()) -> hls_generated_files:output(result()).
emit_stream(Config) ->
    #{files := Files, result := Result} = emit_mode(Config, stream),
    #{files := ParentFiles, inputs := Inputs, outputs := Outputs} =
        Parent = hls_supervisor_stream:emit(Result),
    #{
        files => hls_generated_files:merge([Files, ParentFiles]),
        result => Result#{
            inputs := Inputs, outputs := Outputs, parent_stream => maps:remove(files, Parent)
        }
    }.

%% Raw and framed emission share the same source-defined supervisor and each child core.
-spec emit_mode(config(), raw | stream) -> hls_generated_files:output(result()).
emit_mode(Config, Mode) ->
    Plan = #{children := Children} = plan(Config),
    Generated = [
        {Id, I, child_emit(C, Mode)}
     || {I, {Id, C}} <- lists:enumerate(0, Children)
    ],
    [#{result := #{codecs := DomainCodecs}} | _] = [G || {_, _, G} <- Generated],
    Source = hls_source:library_file(hls_runtime, "runtime/hls_supervisor_lifecycle.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    InputFields = fields(Forms, supervisor_input),
    StateFields = fields(Forms, supervisor_state),
    ChildFields = fields(Forms, supervisor_child),
    OutputFields = fields(Forms, supervisor_output),
    Codecs = DomainCodecs#{
        supervisor_operation => maps:get(op, InputFields),
        supervisor_phase => maps:get(phase, StateFields),
        supervisor_reason => maps:get(reason, StateFields),
        supervisor_status => maps:get(status, OutputFields),
        child_phase => maps:get(phase, ChildFields),
        child_policy => maps:get(policy, InputFields)
    },
    Words = max(
        10,
        (max(
            hls_records:width(hls_records:find(Forms, supervisor_input)),
            hls_records:width(hls_records:find(Forms, supervisor_output))
        ) + 31) div 32
    ),
    Supervisor = xls_parse:to_artifact(Source, #{frame_payload_words => Words}),
    Parent = xls_parse:to_artifact(
        hls_source:library_file(
            hls_runtime,
            "runtime/hls_domain_lifecycle.erl"
        ),
        #{frame_payload_words => Words}
    ),
    Count = length(Children),
    {ControlInputs, ControlOutputs} = control_ports(Count, Codecs),
    Interfaces = [#{id => Id, index => I, interface => R} || {Id, I, #{result := R}} <- Generated],
    {Inputs, Outputs} =
        case Mode of
            raw -> sv_domain_supervisor:ports(Interfaces, ControlInputs, ControlOutputs);
            stream -> sv_domain_supervisor:stream_ports(Interfaces, ControlInputs, ControlOutputs)
        end,
    Files = hls_generated_files:merge([
        child_files(Generated, Mode),
        hls_generated_files:prefix("supervisor", xls_emitted:dependencies(Supervisor)),
        hls_generated_files:prefix("supervisor", xls_emitted:dependencies(Parent)),
        #{
            "supervisor/supervisor_controller.x" => xls_emitted:bytes(Supervisor),
            "supervisor/parent_controller.x" => xls_emitted:bytes(Parent),
            "supervisor/supervisor_codes.x" => constants(Codecs),
            "supervisor/supervisor.x" => render(Plan, ControlInputs, ControlOutputs),
            "supervisor/controller.sv" => sv_protocol_ports:emit(
                ControlInputs,
                ControlOutputs,
                "supervisor_control",
                "supervisor_control_core"
            ),
            case Mode of
                raw -> "supervisor/protocol_supervisor.sv";
                stream -> "supervisor/protocol_supervisor_stream_raw.sv"
            end =>
                case Mode of
                    raw ->
                        sv_domain_supervisor:emit(Interfaces, ControlInputs, ControlOutputs);
                    stream ->
                        sv_domain_supervisor:emit_stream(Interfaces, ControlInputs, ControlOutputs)
                end
        }
    ]),
    StateBits = hls_records:width(hls_records:find(Forms, supervisor_state)),
    ChildBits = hls_records:width(hls_records:find(Forms, supervisor_child)),
    ParentBits = hls_records:width(hls_records:find(Forms, domain_state)),
    #{
        files => Files,
        result => #{
            inputs => Inputs,
            outputs => Outputs,
            children => Interfaces,
            codecs => Codecs,
            plan => Plan,
            frame_payload_words => Words,
            control_state_bits => StateBits + Count * ChildBits + ParentBits + 16 + 1 + 32 + 64 + 1 +
                4 * 64 + 64,
            eligible => false
        }
    }.

%% The record resolver owns enum ordering and every packed field width.
-spec fields([hls_source:form()], atom()) -> #{atom() => hls_type:descriptor()}.
fields(Forms, Name) -> maps:from_list(hls_records:fields(hls_records:find(Forms, Name))).

%% Each child keeps its own DSLX namespace and frame layout; only RTL module names differ.
-spec child_files(
    [
        {atom(), non_neg_integer(), hls_generated_files:output(hls_protocol_domain:result())}
    ],
    raw | stream
) -> #{string() => iodata()}.
child_files(Generated, Mode) ->
    hls_generated_files:merge([
        begin
            Prefix = child_prefix(I),
            Wrapper =
                case Mode of
                    raw -> "domain/protocol_domain.sv";
                    stream -> "domain/domain_stream.sv"
                end,
            G = maps:without(["domain/protocol_domain.sv", "domain/domain_stream.sv"], Files),
            hls_generated_files:prefix(Prefix, G#{
                Wrapper =>
                    sv_protocol_ports:emit(Inputs, Outputs, Prefix, Prefix ++ "_core")
            })
        end
     || {_, I, #{files := Files, result := #{inputs := Inputs, outputs := Outputs}}} <- Generated
    ]).

-doc "Writes a fresh portable source bundle with separate child/control XLS units and retained interface.etf. Does not run tools or attach a deployment. Startup failures retain partial evidence; a physical reset or lost allocation state requires host exclusion and a newly reserved identity grant.".
-spec write(config(), file:filename()) -> map().
write(Config, Directory) -> write_bundle(Config, Directory, raw).

-doc "Writes a fresh portable supervised stream bundle, per-child runtime interfaces and parent framing interface. Independent child application/management lanes preserve bounded reply ownership; deployment owns physical session isolation.".
-spec write_stream(config(), file:filename()) -> map().
write_stream(Config, Directory) -> write_bundle(Config, Directory, stream).

%% Each source module is compiled once; only the selected wrapper and physical pins differ.
-spec write_bundle(config(), file:filename(), raw | stream) -> map().
write_bundle(Config, Directory, Mode) ->
    Generated =
        #{result := Result = #{children := Children, frame_payload_words := Words}} =
        case Mode of
            raw -> emit(Config);
            stream -> emit_stream(Config)
        end,
    _ = hls_generated_files:write(Generated, Directory),
    #{libraries := Libraries, imports := Support} = hls_build_support:layout([]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    ok = hls_compile:configure_support(Directory, hls_frame_layout:new(Words)),
    ChildUnits = [
        begin
            Prefix = child_prefix(I),
            ChildDir = filename:join(Directory, Prefix),
            #{frame_payload_words := ChildWords} = Interface,
            ok = hls_artifact_bundle:snapshot(ChildDir, Libraries),
            ok = hls_compile:configure_support(ChildDir, hls_frame_layout:new(ChildWords)),
            {Source, Top, Output, Wrapper} =
                case Mode of
                    raw ->
                        {"domain.x", "domain_clock", "core.v", "protocol_domain.sv"};
                    stream ->
                        {"domain_stream.x", "domain_stream_clock", "stream_core.v",
                            "domain_stream.sv"}
                end,
            unit(
                Prefix ++ "/domain",
                Prefix ++ "/domain/" ++ Source,
                Top,
                Prefix ++ "_core",
                Prefix ++ "/domain/" ++ Output,
                [Prefix ++ "/domain", Prefix ++ "/network", Prefix ++ "/actors", Prefix ++ "/dslx"] ++
                    [Prefix ++ "/" ++ P || P <- Support],
                [Prefix ++ "/domain/" ++ Output, Prefix ++ "/domain/" ++ Wrapper],
                ChildWords
            )
        end
     || #{index := I, interface := Interface} <- Children
    ],
    SupervisorUnit = unit(
        "supervisor",
        "supervisor/supervisor.x",
        "supervisor_clock",
        "supervisor_control_core",
        "supervisor/core.v",
        ["supervisor" | Support],
        [
            "supervisor/core.v",
            "supervisor/controller.sv",
            case Mode of
                raw -> "supervisor/protocol_supervisor.sv";
                stream -> "supervisor/protocol_supervisor_stream_raw.sv"
            end
        ],
        Words
    ),
    ok = file:write_file(filename:join(Directory, "interface.etf"), term_to_binary(Result), [
        exclusive
    ]),
    hls_artifact_bundle:finish(
        Directory,
        ChildUnits ++ [SupervisorUnit] ++
            case Mode of
                raw -> [];
                stream -> [maps:get(unit, maps:get(parent_stream, Result))]
            end,
        #{kind => static_supervisor, backend => source_protocol}
    ).

%% Independent output directories keep compiler products and support imports unambiguous.
-spec unit(
    string(),
    string(),
    string(),
    string(),
    string(),
    [string()],
    [string()],
    hls_frame_layout:words()
) -> hls_artifact_bundle:unit().
unit(Directory, Source, Top, Module, Output, Imports, Rtl, Words) ->
    Profile = hls_build_profile:owner(hls_frame_layout:new(Words)),
    #{
        role => <<".">>,
        directory => b(Directory),
        source => b(Source),
        top => b(Top),
        module => b(Module),
        output => b(Output),
        dslx_path => [b(P) || P <- Imports],
        rtl => [b(P) || P <- Rtl],
        codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
    }.

%% A generated index, not an application atom, forms an HDL identifier.
-spec child_prefix(non_neg_integer()) -> string().
child_prefix(I) -> "child_" ++ integer_to_list(I).

%% Manifest strings use portable UTF-8 binaries.
-spec b(string()) -> binary().
b(S) -> unicode:characters_to_binary(S).

%% The management scanner sees current child lifecycle state, never application payloads.
-spec control_ports(pos_integer(), #{atom() := hls_type:descriptor()}) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
control_ports(Count, Codecs) ->
    Width = fun(K) -> hls_type:width(maps:get(K, Codecs)) end,
    ParentInputs = [
        {"reset", 1},
        {"management_valid", 1},
        {"management_op", Width(operation)},
        {"expected", 64},
        {"target", 64},
        {"transition", 64},
        {"management_fault", Width(fault)},
        {"grant_valid", 1},
        {"grant_epoch", 64},
        {"grant_first", 64},
        {"grant_last", 64},
        {"slot_valid", 1},
        {"slot_operation", 2},
        {"slot_epoch", 64},
        {"slot_index", 32},
        {"slot_expected", 64}
    ],
    ParentOutputs = [
        {"management_ready", 1},
        {"management_response_valid", 1},
        {"domain_status", Width(status)},
        {"domain_action", Width(action)},
        {"domain_phase", Width(phase)},
        {"domain_current", 64},
        {"domain_previous", 64},
        {"domain_target", 64},
        {"domain_transition", 64},
        {"domain_fault", Width(fault)},
        {"domain_admission", 1},
        {"domain_initialized", 1},
        {"grant_ready", 1},
        {"grant_accepted", 1},
        {"grant_response_valid", 1},
        {"supervisor_phase", Width(supervisor_phase)},
        {"supervisor_reason", Width(supervisor_reason)},
        {"grant_next", 64},
        {"supervisor_started", 16},
        {"supervisor_retired", 16},
        {"local_seconds", 64},
        {"selected_child", 16},
        {"children_reset", 1},
        {"slot_ready", 1},
        {"slot_response_valid", 1},
        {"slot_status", Width(supervisor_status)},
        {"slot_result_index", 32},
        {"slot_phase", Width(child_phase)},
        {"slot_target", 64}
    ],
    ChildInputs = lists:append([
        [
            {child_prefix(I) ++ "_observed_" ++ N, W}
         || {N, W} <-
                [
                    {"phase", Width(phase)},
                    {"current", 64},
                    {"previous", 64},
                    {"target", 64},
                    {"transition", 64},
                    {"fault", Width(fault)},
                    {"reusable", 1}
                ]
        ]
     || I <- lists:seq(0, Count - 1)
    ]),
    ChildOutputs = lists:append([
        [
            {child_prefix(I) ++ "_" ++ N, W}
         || {N, W} <-
                [
                    {"management_valid", 1},
                    {"management_op", Width(operation)},
                    {"expected", 64},
                    {"target", 64},
                    {"transition", 64},
                    {"management_fault", Width(fault)}
                ]
        ]
     || I <- lists:seq(0, Count - 1)
    ]),
    {ParentInputs ++ ChildInputs, ParentOutputs ++ ChildOutputs}.

%% Only static topology/pin shape is specialized; restart decisions stay in compiled Erlang.
-spec render(plan(), [{string(), pos_integer()}], [{string(), pos_integer()}]) -> binary().
render(
    #{
        children := Children,
        policies := Policies,
        initial := Initial,
        intensity := Intensity,
        period := Period,
        clock_hz := Hz
    },
    Inputs,
    Outputs
) ->
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_lowering), "xls/templates/supervisor.x.in")
    ),
    Count = length(Children),
    xls_template:render(Template, [
        {<<"@@COUNT@@">>, integer_to_binary(Count)},
        {<<"@@INITIAL@@">>, integer_to_binary(Initial)},
        {<<"@@CHILD_POLICIES@@">>,
            lists:join(",", [
                "supervisor_codes::CHILD_POLICY_" ++
                    string:uppercase(atom_to_list(maps:get(Id, Policies)))
             || {Id, _} <- Children
            ])},
        {<<"@@CHILD_REUSABLE@@">>,
            lists:join(",", [
                "io." ++ child_prefix(I) ++ "_observed_reusable"
             || I <- lists:seq(0, Count - 1)
            ])},
        {<<"@@INTENSITY@@">>, integer_to_binary(Intensity)},
        {<<"@@PERIOD@@">>, integer_to_binary(Period)},
        {<<"@@CLOCK_HZ@@">>, integer_to_binary(Hz)},
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@CHILD_OBSERVATIONS@@">>,
            lists:join(",\n", [observation(I) || I <- lists:seq(0, Count - 1)])},
        {<<"@@CHILD_COMMANDS@@">>, [command_fields(I) || I <- lists:seq(0, Count - 1)]}
    ]).

%% Field order is the physical sampled-port order.
-spec structure(string(), [{string(), pos_integer()}]) -> iodata().
structure(Name, Fields) ->
    [
        "pub struct ",
        Name,
        " {\n",
        [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields],
        "}\n"
    ].

%% Construct the compiled kernel's own record type, avoiding structural type aliases across modules.
-spec observation(non_neg_integer()) -> iodata().
observation(I) ->
    [
        "supervisor_controller::Domainstate {",
        lists:join(",", [
            [N, ":io.", child_prefix(I), "_observed_", N]
         || N <- ["phase", "current", "previous", "target", "transition", "fault"]
        ]),
        "}"
    ].

%% One selected slot can issue a command; all other child management ports stay idle.
-spec command_fields(non_neg_integer()) -> iodata().
command_fields(I) ->
    Prefix = child_prefix(I),
    [
        [
            Prefix,
            "_management_valid: !io.reset && selected == u16:",
            integer_to_list(I),
            " && manager_reply.command_valid,\n"
        ],
        [Prefix, "_management_op: manager_reply.command.op,\n"],
        [
            [Prefix, "_", N, ": manager_reply.command.", N, ",\n"]
         || N <- ["expected", "target", "transition"]
        ],
        [Prefix, "_management_fault: manager_reply.command.fault,\n"]
    ].

%% Source type providers remain the authority for every atom encoding.
-spec constants(#{atom() := hls_type:descriptor()}) -> iodata().
constants(Codecs) ->
    [
        [constant(Kind, Member, Descriptor) || Member <- Members]
     || {Kind, Descriptor = {hls_type, hls_enum, enum, [Members]}} <- lists:sort(
            maps:to_list(Codecs)
        )
    ].

%% Compact source-derived enum literals keep handwritten DSLX independent of integer tag choices.
-spec constant(atom(), atom(), hls_type:descriptor()) -> iodata().
constant(Kind, Member, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Code:Width>> = hls_type:pack(Member, Descriptor),
    [
        "pub const ",
        string:uppercase(atom_to_list(Kind) ++ "_" ++ atom_to_list(Member)),
        " = uN[",
        integer_to_list(Width),
        "]:",
        integer_to_list(Code),
        ";\n"
    ].

%% Supervised framing reuses the checked raw domain and gives each child its own transport storage.
-spec child_emit(hls_source_config:network() | file:filename(), raw | stream) ->
    hls_generated_files:output(hls_protocol_domain:result()).
child_emit(Filename, Mode) when is_list(Filename); is_binary(Filename) ->
    child_emit(hls_source_config:read(Filename), Mode);
child_emit(#{inspection := process}, _) ->
    hls_diagnostic:raise(
        supervisor,
        supervised_inspection_unavailable,
        <<"Compiled supervisors do not bind process inspection across parent admission; use host-managed domain inspection.">>,
        #{path => [children, inspection], value => process}
    );
child_emit(Config, raw) ->
    hls_protocol_domain:emit(Config);
child_emit(Config, stream) ->
    #{
        files := RawFiles,
        result := Raw = #{codecs := Codecs, stream := Bindings, frame_payload_words := Words}
    } = hls_protocol_domain:emit(Config, stream),
    #{files := StreamFiles} = Stream = hls_domain_stream:emit_supervised(Raw),
    Transport = maps:remove(files, Stream),
    Runtime = Bindings#{
        codecs => Codecs,
        frame_payload_words => Words,
        transport => Transport,
        supervision => local
    },
    {Inputs, Outputs} = hls_domain_stream:supervised_ports(Codecs),
    #{
        files => hls_generated_files:merge([
            RawFiles,
            StreamFiles,
            #{"domain/interface.etf" => term_to_binary(Runtime)}
        ]),
        result => Raw#{
            inputs := Inputs,
            outputs := Outputs,
            transport => Transport,
            runtime_interface => Runtime
        }
    }.
