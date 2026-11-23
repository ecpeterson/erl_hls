-module(hls_build_profile).
-moduledoc """
Declared hardware policy shared by fabric builders and prepared-source experiments. hls_source_build and hls_scheduler_build use these profiles to retain placement, ordinary-frame ABI and supported schedules, then flags/2 renders literal XLS options. Actual tool identities and measured timing belong to external compilation.
""".
%% Source-protocol policy construction.
-export([protocol/2, owner/0, owner/1]).

%% Channel-scheduler and prepared-source policy.
-export([scheduler/2, scheduler/3, experiment/1]).

%% Literal external-tool flags.
-export([flags/2]).
%% Shared type contracts.
-export_type([profile/0, schedule_options/0, experiment_options/0, experiment/0]).

%% XLS schedule counts and explicit channel-delay budgets fit its integer option range.
-type count() :: 1..((1 bsl 32) - 1).
%% The name is passed to XLS as one option; custom models remain tool-owned.
-type delay_model() :: atom() | string() | binary().

-doc "Channel-scheduler options. Omitted counts select two pipeline stages and initiation interval one; explicit tool_default omits the initiation-interval flag; the default unit delay model and zero result delay are scheduling policies, not physical timing estimates. Sampled-clock profiles accept no such overrides.".
-type schedule_options() :: #{
    pipeline_stages => count(),
    initiation_interval => count() | tool_default,
    delay_model => delay_model(),
    executor_result_delay => 0..((1 bsl 32) - 1)
}.

%% Retained source placement omits source files, constructor arguments and packaging paths.
-type source_placement() ::
    #{
        kind := hls_source_build:kind(),
        actor_limit := 1..(1 bsl 16),
        native_actors => [hls_protocol_topology:id(), ...],
        arithmetic_groups := [[hls_protocol_topology:id(), ...]],
        activation => hls_source_config:activation(),
        inspection => hls_source_config:inspection(),
        control => rectangle,
        device => hls_source_config:device(),
        host => hls_source_config:endpoint(),
        service => hls_source_config:endpoint(),
        devices => #{hls_source_config:device() => hls_source_config:role()},
        limits => hls_source_config:limits()
    }
    | #{kind := local_owner}.
%% This names the current ordinary actor ABI; bridge envelopes and compact captures are different formats.
-type frame_abi() :: hls_frame_layout:descriptor().
%% Input/output register policy belongs to the clock owner, not an optimization preference.
-type schedule() :: #{
    pipeline_stages := count(),
    delay_model := binary(),
    flop_inputs := false,
    flop_outputs := boolean(),
    fifo_module := default | none,
    initiation_interval => count() | tool_default,
    executor_result_delay => 0..((1 bsl 32) - 1)
}.
%% No tool is inspected or launched while resolving a source profile.
-type tools() :: #{provider := xls, identity := external_compilation}.

-doc "A resolved hardware policy. Source placements retain checked configuration shape; the owning source planner still validates graph ownership and capabilities. Scheduler placement is normalized by xls_fabric_topology_profile. Tool identity is intentionally deferred to external compilation, which records actual executable and library hashes.".
-type profile() ::
    #{
        backend := source_protocol,
        placement := source_placement(),
        frame_abi := frame_abi(),
        schedules := #{sampled_clock := schedule(), gateway => schedule()},
        tools := tools()
    }
    | #{
        backend := channel_scheduler,
        placement := xls_fabric_topology_profile:profile() | prepared_source,
        frame_abi := frame_abi(),
        schedules := #{channel := schedule()},
        tools := tools(),
        postprocess => #{completion_storage := registers | lutram}
    }.

-doc "Policy for already prepared experiment DSLX. Schedule defaults match the public channel scheduler; tool_default explicitly preserves an unspecified XLS initiation interval. Completion storage selects a backend legalization without changing the logical FIFO contract.".
-type experiment_options() :: #{
    schedule => schedule_options(), completion_storage => registers | lutram
}.

-doc "Versioned prepared-source policy and its rendered XLS flags. Encode through hls_diagnostic:json_value/1 for JSON. This trusted build record describes requested policy, not source eligibility, an implemented placement or measured tool identity.".
-type experiment() :: #{version := 1, profile := profile(), codegen_flags := [binary()]}.

-doc "Resolves source-protocol policy after validating the selected configuration shape. Retains ownership and interface settings without source paths or constructor values. The sampled feedback clock has one stage and no boundary flops; an application gateway additionally has its separate two-stage channel schedule. Invalid config fields, including schedule overrides, fail before source compilation.".
-spec protocol(hls_source_build:kind(), hls_source_config:config()) -> profile().
protocol(Kind, Config) ->
    Checked = hls_source_config:validate(Kind, Config),
    Placement0 = maps:with(
        [
            actor_limit,
            native_actors,
            arithmetic_groups,
            activation,
            inspection,
            control,
            device,
            host,
            service,
            devices,
            limits
        ],
        Checked
    ),
    Placement = protocol_defaults(Kind, Placement0#{
        kind => Kind,
        arithmetic_groups => maps:get(arithmetic_groups, Checked, [])
    }),
    Schedules =
        case Kind of
            application -> #{sampled_clock => sampled_clock(), gateway => channel(2, <<"unit">>)};
            _ -> #{sampled_clock => sampled_clock()}
        end,
    profile(
        source_protocol,
        Placement,
        Schedules,
        hls_frame_layout:new(maps:get(frame_payload_words, Checked, 3))
    ).

-doc "Returns the fixed schedule for one ordinary or sender-local inbox actor owner. Its sampled command and observation pins require valid/ready asserted every clock; compilation does not establish connected-protocol admission.".
-spec owner() -> profile().
owner() -> owner(hls_frame_layout:default()).

-doc "Returns an owner profile with its selected ordinary frame layout; compact captures and debug observations keep their own widths.".
-spec owner(hls_frame_layout:layout()) -> profile().
owner(Layout) ->
    profile(source_protocol, #{kind => local_owner}, #{sampled_clock => sampled_clock()}, Layout).

-doc "Normalizes scheduler placement and requested XLS scheduling options. Rejects unknown options, noninteger counts or delays, and malformed delay-model names. Result delay reserves scheduler budget at result sends; it changes neither requested pipeline depth nor physical time by itself.".
-spec scheduler(xls_fabric_topology_profile:profile(), schedule_options()) -> profile().
scheduler(Placement, Options) ->
    scheduler(
        Placement,
        Options,
        hls_frame_layout:new(maps:get(frame_payload_words, Placement, 3))
    ).

-doc "Normalizes scheduler policy with a checked ordinary-frame layout; every emitted actor and mailbox must use this ABI.".
-spec scheduler(
    xls_fabric_topology_profile:profile(), schedule_options(), hls_frame_layout:layout()
) -> profile().
scheduler(Placement, Options, Layout) ->
    profile(
        channel_scheduler,
        xls_fabric_topology_profile:normalize(Placement#{
            frame_payload_words => hls_frame_layout:payload_words(Layout)
        }),
        #{channel => channel_schedule(Options)},
        Layout
    ).

-doc "Resolves channel scheduling and completion-storage policy without reading source or invoking XLS. Rejects unknown fields and unsupported storage; prepared_source records that placement was performed elsewhere. The returned flags use the same renderer as public scheduler bundles and cannot select sampled-clock retiming.".
-spec experiment(experiment_options()) -> experiment().
experiment(Options) when is_map(Options) ->
    case maps:keys(Options) -- [schedule, completion_storage] of
        [] ->
            ok;
        Unknown ->
            hls_diagnostic:raise(
                configuration,
                unknown_experiment_options,
                <<"Experiment policy contains unsupported fields.">>,
                #{value => lists:sort(Unknown)}
            )
    end,
    Storage =
        case maps:get(completion_storage, Options, registers) of
            Value when Value =:= registers; Value =:= lutram -> Value;
            Other ->
                hls_diagnostic:raise(
                    configuration,
                    invalid_completion_storage,
                    <<"Completion storage must be registers or lutram.">>,
                    #{field => [completion_storage], value => Other}
                )
        end,
    Profile = (profile(
        channel_scheduler,
        prepared_source,
        #{channel => channel_schedule(maps:get(schedule, Options, #{}))}
    ))#{
        postprocess => #{completion_storage => Storage}
    },
    #{version => 1, profile => Profile, codegen_flags => flags(Profile, channel)};
experiment(Other) ->
    hls_diagnostic:raise(
        configuration,
        invalid_experiment_options,
        <<"Experiment policy must be a map.">>,
        #{value => Other}
    ).

%% Public topology and prepared-source experiments resolve one channel schedule authority.
-spec channel_schedule(schedule_options()) -> schedule().
channel_schedule(Options) ->
    checked_options(Options),
    Stages = integer_option(pipeline_stages, Options, 2, 1),
    Interval =
        case maps:get(initiation_interval, Options, 1) of
            tool_default -> tool_default;
            _ -> integer_option(initiation_interval, Options, 1, 1)
        end,
    Delay = integer_option(executor_result_delay, Options, 0, 0),
    Model = delay_model(maps:get(delay_model, Options, unit)),
    (channel(Stages, Model))#{initiation_interval => Interval, executor_result_delay => Delay}.

-doc "Renders the selected retained schedule as ordered XLS codegen arguments. Unit module names, RAM bindings and tool-owned delay tables are supplied by packaging/execution. Requesting a schedule absent from this backend fails; source feedback latency cannot be changed through this API.".
-spec flags(profile(), sampled_clock | gateway | channel) -> [binary()].
flags(#{backend := Backend, schedules := Schedules}, Kind) ->
    case maps:find(Kind, Schedules) of
        {ok, Schedule} ->
            schedule_flags(Schedule);
        error ->
            hls_diagnostic:raise(
                configuration,
                unsupported_build_schedule,
                <<"This backend has no requested schedule.">>,
                #{backend => Backend, value => Kind}
            )
    end.

%% The source configuration remains authoritative for explicit mode choices.
-spec protocol_defaults(hls_source_build:kind(), map()) -> source_placement().
protocol_defaults(transport, Placement) ->
    Placement;
protocol_defaults(Kind, Placement) ->
    Activation =
        case Kind of
            network -> automatic;
            boundary -> automatic;
            _ -> explicit_start
        end,
    maps:merge(#{activation => Activation, inspection => none}, Placement).

%% Profiles carry no executable identity until an external build has inspected real tools.
-spec profile(
    source_protocol | channel_scheduler,
    source_placement() | xls_fabric_topology_profile:profile() | prepared_source,
    #{sampled_clock => schedule(), gateway => schedule(), channel => schedule()}
) -> profile().
profile(Backend, Placement, Schedules) ->
    profile(Backend, Placement, Schedules, hls_frame_layout:default()).

%% Layout descriptors are derived from the compiler authority rather than copied ABI literals.
-spec profile(
    source_protocol | channel_scheduler,
    source_placement() | xls_fabric_topology_profile:profile() | prepared_source,
    #{sampled_clock => schedule(), gateway => schedule(), channel => schedule()},
    hls_frame_layout:layout()
) -> profile().
profile(Backend, Placement, Schedules, Layout) ->
    #{
        backend => Backend,
        placement => Placement,
        frame_abi => hls_frame_layout:descriptor(Layout),
        schedules => Schedules,
        tools => #{provider => xls, identity => external_compilation}
    }.

%% Feedback circuits expose existing registers directly through sampled pins.
-spec sampled_clock() -> schedule().
sampled_clock() ->
    #{
        pipeline_stages => 1,
        delay_model => <<"unit">>,
        flop_inputs => false,
        flop_outputs => false,
        fifo_module => default
    }.

%% Channel procs retain output flops and inline FIFOs under their existing schedule.
-spec channel(count(), binary()) -> schedule().
channel(Stages, Model) ->
    #{
        pipeline_stages => Stages,
        delay_model => Model,
        flop_inputs => false,
        flop_outputs => true,
        fifo_module => none
    }.

%% Preserve option ordering for existing release identities and replay checks.
-spec schedule_flags(schedule()) -> [binary()].
schedule_flags(
    #{
        pipeline_stages := Stages,
        delay_model := Model,
        flop_outputs := Outputs,
        fifo_module := Fifo
    } = Schedule
) ->
    Base = [
        integer_flag(<<"pipeline_stages">>, Stages),
        <<"--delay_model=", Model/binary>>,
        <<"--flop_inputs=false">>,
        <<"--flop_outputs=", (atom_to_binary(Outputs))/binary>>,
        <<"--use_system_verilog=false">>,
        <<"--reset=reset">>
    ],
    FifoFlags =
        case Fifo of
            default -> [];
            none -> [<<"--fifo_module=">>]
        end,
    DelayFlags =
        case maps:get(executor_result_delay, Schedule, 0) of
            0 ->
                [];
            Delay ->
                [
                    <<"--additional_channel_delay_ps=_result_out:send=",
                        (integer_to_binary(Delay))/binary>>
                ]
        end,
    IntervalFlags =
        case maps:find(initiation_interval, Schedule) of
            error -> [];
            {ok, tool_default} -> [];
            {ok, Interval} -> [integer_flag(<<"worst_case_throughput">>, Interval)]
        end,
    Base ++ FifoFlags ++ DelayFlags ++ IntervalFlags.

%% Build options cross a public boundary; a misspelling must not silently select defaults.
-spec checked_options(term()) -> ok.
checked_options(Options) when is_map(Options) ->
    case
        maps:keys(Options) --
            [pipeline_stages, initiation_interval, delay_model, executor_result_delay]
    of
        [] ->
            ok;
        Unknown ->
            hls_diagnostic:raise(
                configuration,
                unknown_schedule_options,
                <<"Scheduler options contain unsupported fields.">>,
                #{field => [schedule], value => lists:sort(Unknown)}
            )
    end;
checked_options(Other) ->
    invalid([], <<"map of scheduler options">>, Other).

%% Do not accept booleans, floats or negative integers as scheduling counts.
-spec integer_option(
    pipeline_stages | initiation_interval | executor_result_delay,
    schedule_options(),
    integer(),
    0 | 1
) -> non_neg_integer().
integer_option(Key, Options, Default, Minimum) ->
    case maps:get(Key, Options, Default) of
        Value when is_integer(Value), Value >= Minimum, Value < (1 bsl 32) -> Value;
        Value -> invalid([Key], <<"integer in the supported 32-bit range">>, Value)
    end.

%% Model names are one XLS identifier, never shell fragments or additional arguments.
-spec delay_model(term()) -> binary().
delay_model(Model) when is_atom(Model), Model =/= true, Model =/= false ->
    delay_model(atom_to_binary(Model));
delay_model(Model) when is_binary(Model) ->
    case re:run(Model, <<"^[A-Za-z_][A-Za-z0-9_-]*$">>, [{capture, none}, dollar_endonly]) of
        match -> Model;
        nomatch -> invalid([delay_model], <<"XLS delay-model identifier">>, Model)
    end;
delay_model(Model) when is_list(Model) ->
    case catch unicode:characters_to_binary(Model) of
        Text when is_binary(Text) -> delay_model(Text);
        _ -> invalid([delay_model], <<"XLS delay-model identifier">>, Model)
    end;
delay_model(Model) ->
    invalid([delay_model], <<"XLS delay-model identifier">>, Model).

%% Render integers only after their public-input check has established the option contract.
-spec integer_flag(binary(), non_neg_integer()) -> binary().
integer_flag(Name, Value) -> <<"--", Name/binary, "=", (integer_to_binary(Value))/binary>>.

%% Keep rejected input tied to the schedule field for CLI diagnostics.
-spec invalid([atom()], binary(), term()) -> no_return().
invalid(Field, Expected, Value) ->
    hls_diagnostic:raise(
        configuration,
        invalid_schedule_option,
        <<"Scheduler option has an invalid value.">>,
        #{field => [schedule | Field], expected => Expected, value => Value}
    ).
