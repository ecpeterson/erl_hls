-module(hls_implementation_constraints).
-moduledoc """
Owns process-free implementation constraints shared by topology builders.

The contract covers topology names, bounded channel and egress capacities,
ordinary-frame capacity, and the retained XLS scheduling vocabulary. Backend
wrappers still own reserved target names, observation options, placement, RAM
selection, and tool execution. Ordered flag rendering preserves the two
existing bundle boundaries without making either builder authoritative for
the underlying schedule.
""".

%% Shared topology-profile normalization and identifier policy.
-export([normalize_topology/3, identifier/3, reserved_identifier/5, egress_depth/2]).
%% Shared retained schedules and their existing bundle encodings.
-export([
    sampled_schedule/0,
    gateway_schedule/0,
    channel_schedule/1,
    standalone_topology_schedule/1,
    schedule_flags/2
]).
%% Process-free implementation constraint types.
-export_type([egress_policy/0, schedule/0, schedule_options/0]).

-define(U32_MAX, ((1 bsl 32) - 1)).

-doc "An explicit nonnegative egress depth or capacity derived from one actor effect burst.".
-type egress_policy() :: burst | 0..?U32_MAX.

-doc "Optional channel-scheduler counts and one tool-owned delay-model name.".
-type schedule_options() :: #{
    pipeline_stages => 1..?U32_MAX,
    initiation_interval => 1..?U32_MAX | tool_default,
    delay_model => atom() | string() | binary(),
    executor_result_delay => 0..?U32_MAX
}.

-doc "A checked external compilation schedule; result delay and initiation interval occur only on channel-scheduler requests.".
-type schedule() :: #{
    pipeline_stages := pos_integer(),
    delay_model := binary(),
    flop_inputs := false,
    flop_outputs := boolean(),
    fifo_module := default | none,
    initiation_interval => 1..?U32_MAX | tool_default,
    executor_result_delay => 0..?U32_MAX
}.

-doc "Validates the common topology profile keys, target name, channel/egress bounds, and ordinary-frame capacity. `ExtraKeys` remain backend-owned; `NameValidator` applies target-specific reserved-name policy. Returns the original extras plus normalized common fields.".
-spec normalize_topology(term(), [atom()], fun((term(), term()) -> string())) -> map().
normalize_topology(Profile, ExtraKeys, NameValidator) when
    is_map(Profile), is_list(ExtraKeys), is_function(NameValidator, 2)
->
    Required = [actor_egress_depth, channel_depth, name],
    Keys = lists:sort(maps:keys(Profile)),
    Allowed = Required ++ [frame_payload_words | ExtraKeys],
    case {Required -- Keys, Keys -- Allowed} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    #{
        name := Name0,
        channel_depth := Depth,
        actor_egress_depth := EgressDepth
    } = Profile,
    Name = NameValidator(Name0, topology_name),
    ok = validate_channel_depth(Depth),
    ok = validate_egress_depth(EgressDepth),
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Profile, 3)),
    Profile#{
        name := Name,
        frame_payload_words => hls_frame_layout:payload_words(Layout)
    };
normalize_topology(Profile, _ExtraKeys, _NameValidator) ->
    error({invalid_dslx_profile, Profile}).

-doc "Normalizes a lowercase implementation identifier after asking `Reserved` whether its checked spelling is unavailable in the target context.".
-spec identifier(term(), term(), fun((string(), term()) -> boolean())) -> string().
identifier(Name, Context, Reserved) when is_atom(Name) ->
    identifier(atom_to_list(Name), Context, Reserved);
identifier(Name, Context, Reserved) when is_list(Name), is_function(Reserved, 2) ->
    case re:run(Name, "^[a-z][a-z0-9_]*$", [{capture, none}]) of
        match ->
            case Reserved(Name, Context) of
                true -> error({reserved_dslx_identifier, Context, Name});
                false -> Name
            end;
        nomatch ->
            error({invalid_dslx_identifier, Context, Name})
    end;
identifier(Name, Context, _Reserved) ->
    error({invalid_dslx_identifier, Context, Name}).

-doc "Applies the shared topology target-name policy after lexical validation. `Keyword` supplies the target grammar; `ModuleContexts` and `ReservedModules` extend the compiler module namespace without duplicating its common stems or library names.".
-spec reserved_identifier(
    string(),
    term(),
    fun((string()) -> boolean()),
    [atom()],
    [string()]
) -> boolean().
reserved_identifier(_Name, {actor_output, _}, _Keyword, _ModuleContexts, _ReservedModules) ->
    false;
reserved_identifier(_Name, external_id, _Keyword, _ModuleContexts, _ReservedModules) ->
    false;
reserved_identifier(_Name, ingress_id, _Keyword, _ModuleContexts, _ReservedModules) ->
    false;
reserved_identifier(_Name, ingress_target, _Keyword, _ModuleContexts, _ReservedModules) ->
    false;
reserved_identifier(Name, Context, Keyword, ModuleContexts, ReservedModules) ->
    case module_context(Context, ModuleContexts) of
        true ->
            reserved_module(Name, Keyword, ReservedModules);
        false ->
            Keyword(Name) orelse lists:member(Name, ["spawn", "while"])
    end.

-doc "Resolves `burst` to the remaining explicit FIFO capacity after its registered producer, or validates and returns a literal depth. Invalid literals raise the shared `{egress_depth, Value}` error.".
-spec egress_depth(egress_policy(), non_neg_integer()) -> non_neg_integer().
egress_depth(burst, MaxEntryEffects) when is_integer(MaxEntryEffects), MaxEntryEffects >= 0 ->
    max(0, MaxEntryEffects - 1);
egress_depth(burst, MaxEntryEffects) ->
    error({max_entry_effects, MaxEntryEffects});
egress_depth(Depth, _MaxEntryEffects) ->
    ok = validate_egress_depth(Depth),
    Depth.

-doc "Returns the fixed one-stage schedule for sampled feedback interfaces; it makes no physical timing claim.".
-spec sampled_schedule() -> schedule().
sampled_schedule() ->
    #{
        pipeline_stages => 1,
        delay_model => <<"unit">>,
        flop_inputs => false,
        flop_outputs => false,
        fifo_module => default
    }.

-doc "Returns the fixed two-stage, output-registered gateway schedule without imposing a throughput option.".
-spec gateway_schedule() -> schedule().
gateway_schedule() -> channel(2, <<"unit">>).

-doc "Validates channel-scheduler overrides and returns the retained schedule. Defaults are two stages, initiation interval one, unit delay, and zero result delay; `tool_default` omits the interval flag.".
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

-doc "Validates the standalone topology builder's positive 32-bit stage count and returns its established unit-delay channel schedule. Rejections retain the topology-build diagnostic contract.".
-spec standalone_topology_schedule(pos_integer()) -> schedule().
standalone_topology_schedule(Stages) when
    is_integer(Stages), Stages > 0, Stages =< ?U32_MAX
->
    (channel(Stages, <<"unit">>))#{initiation_interval => 1, executor_result_delay => 0};
standalone_topology_schedule(Stages) ->
    hls_diagnostic:raise(
        topology_build,
        pipeline_stages,
        <<"Pipeline stage count must be a positive integer">>,
        #{value => Stages}
    ).

-doc "Renders one checked schedule at a genuine bundle boundary. `channel` preserves source/scheduler flag order; `standalone_topology` preserves the compiler bundle's earlier interval position.".
-spec schedule_flags(schedule(), channel | standalone_topology) -> [binary()].
schedule_flags(Schedule, channel) ->
    #{
        pipeline_stages := Stages,
        delay_model := Model,
        flop_outputs := Outputs,
        fifo_module := Fifo
    } = Schedule,
    Base = base_flags(Stages, Model, Outputs),
    Base ++ fifo_flags(Fifo) ++ delay_flags(Schedule) ++ interval_flags(Schedule);
schedule_flags(Schedule, standalone_topology) ->
    #{
        pipeline_stages := Stages,
        delay_model := Model,
        flop_outputs := Outputs,
        fifo_module := Fifo
    } = Schedule,
    [integer_flag(<<"pipeline_stages">>, Stages), <<"--delay_model=", Model/binary>>] ++
        interval_flags(Schedule) ++
        lists:nthtail(2, base_flags(Stages, Model, Outputs)) ++
        fifo_flags(Fifo) ++
        delay_flags(Schedule).

%% Requires a positive depth representable by the retained channel contract.
-spec validate_channel_depth(term()) -> ok.
validate_channel_depth(Depth) when
    is_integer(Depth), Depth > 0, Depth =< ?U32_MAX
->
    ok;
validate_channel_depth(Depth) ->
    error({invalid_dslx_channel_depth, Depth}).

%% Accepts a representable nonnegative depth or burst sizing.
-spec validate_egress_depth(term()) -> ok.
validate_egress_depth(burst) ->
    ok;
validate_egress_depth(Depth) when
    is_integer(Depth), Depth >= 0, Depth =< ?U32_MAX
->
    ok;
validate_egress_depth(Depth) ->
    error({egress_depth, Depth}).

%% Channel procs retain output flops and inline FIFOs under their existing schedule.
-spec channel(pos_integer(), binary()) -> schedule().
channel(Stages, Model) ->
    #{
        pipeline_stages => Stages,
        delay_model => Model,
        flop_inputs => false,
        flop_outputs => true,
        fifo_module => none
    }.

%% Shared required flags precede boundary-specific FIFO/delay/interval placement.
-spec base_flags(pos_integer(), binary(), boolean()) -> [binary()].
base_flags(Stages, Model, Outputs) ->
    [
        integer_flag(<<"pipeline_stages">>, Stages),
        <<"--delay_model=", Model/binary>>,
        <<"--flop_inputs=false">>,
        <<"--flop_outputs=", (atom_to_binary(Outputs))/binary>>,
        <<"--use_system_verilog=false">>,
        <<"--reset=reset">>
    ].

%% An empty FIFO module name selects XLS's inline channel implementation.
-spec fifo_flags(default | none) -> [binary()].
fifo_flags(default) -> [];
fifo_flags(none) -> [<<"--fifo_module=">>].

%% Result delay applies only to the named scheduler result-send operation.
-spec delay_flags(schedule()) -> [binary()].
delay_flags(Schedule) ->
    case maps:get(executor_result_delay, Schedule, 0) of
        0 ->
            [];
        Delay ->
            [
                <<"--additional_channel_delay_ps=_result_out:send=",
                    (integer_to_binary(Delay))/binary>>
            ]
    end.

%% An absent or tool-default interval intentionally emits no throughput request.
-spec interval_flags(schedule()) -> [binary()].
interval_flags(Schedule) ->
    case maps:find(initiation_interval, Schedule) of
        error -> [];
        {ok, tool_default} -> [];
        {ok, Interval} -> [integer_flag(<<"worst_case_throughput">>, Interval)]
    end.

%% Build options cross a public boundary; misspellings cannot select defaults.
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

%% Do not accept booleans, floats, negative integers, or values outside the 32-bit contract.
-spec integer_option(
    pipeline_stages | initiation_interval | executor_result_delay,
    schedule_options(),
    integer(),
    0 | 1
) -> non_neg_integer().
integer_option(Key, Options, Default, Minimum) ->
    case maps:get(Key, Options, Default) of
        Value when is_integer(Value), Value >= Minimum, Value =< ?U32_MAX -> Value;
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

%% Actor/family artifacts and backend-supplied instance contexts share one module namespace.
-spec module_context(term(), [atom()]) -> boolean().
module_context({actor_module, _}, _Extra) ->
    true;
module_context(family_module, _Extra) ->
    true;
module_context({Tag, _}, Extra) ->
    lists:member(Tag, Extra);
module_context(Context, Extra) ->
    lists:member(Context, Extra).

%% Common topology support libraries cannot be shadowed by a generated actor artifact.
-spec reserved_module(string(), fun((string()) -> boolean()), [string()]) -> boolean().
reserved_module(Name, Keyword, Extra) ->
    Keyword(Name) orelse
        lists:member(Name, ["spawn", "while"]) orelse
        lists:member(
            Name,
            ["axis", "frame_transport", "arbitration", "hls_spatial_router" | Extra]
        ).
