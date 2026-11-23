-module(xls_protocol_spacetime_ancestry).
-moduledoc "Refines unresolved register-write operands using selected scalar XLS expressions. The capture adapter calls this after publication attribution. Reads refer to pre-edge stored versions through distinct observation lanes; these lanes are not extra hardware ports. Unsupported expressions and unrepresented scalar state remain explicit roots. This records operational operands, not sensitized gates or routed computation paths.".

%% Offline graph enrichment; the caller owns serialization.
-export([attach/3]).
-export_type([observation/0]).

%% Sidecar masks use hexadecimal text so browser decoders never round wide operands.
-type operands() :: #{
    event := binary(),
    write := binary(),
    data_masks := #{binary() => binary()},
    control_masks := #{binary() => binary()},
    unknown := [binary()],
    value_checked := boolean()
}.

-doc "Finite numerical attribution counts and per-write selected operand evidence. Values/masks use the retained encoded RTL widths, never source-layout offsets.".
-type observation() :: #{
    schema := 1,
    writes := non_neg_integer(),
    values_checked := non_neg_integer(),
    values_unknown := non_neg_integer(),
    refined := non_neg_integer(),
    reads := non_neg_integer(),
    operands := [operands()],
    evidence := binary()
}.

%% Existing events stay immutable; roots and resource read-lane declarations are refined explicitly.
-record(state, {
    plan :: map(),
    names :: #{binary() => binary()},
    registers :: #{binary() => map()},
    cycles :: #{non_neg_integer() => [hls_spacetime:event()]},
    roots :: #{{binary(), binary()} => binary()},
    epochs :: [map()],
    incarnation = none :: none | binary(),
    current = #{} :: #{binary() => binary()},
    resources :: #{binary() => hls_spacetime:resource()},
    versions :: #{binary() => hls_spacetime:version()},
    events = [] :: [hls_spacetime:event()],
    added_versions = [] :: [hls_spacetime:version()],
    sequence = 0 :: non_neg_integer(),
    records = 0 :: non_neg_integer(),
    writes = 0 :: non_neg_integer(),
    checked = 0 :: non_neg_integer(),
    unknown = 0 :: non_neg_integer(),
    refined = 0 :: non_neg_integer(),
    reads = 0 :: non_neg_integer(),
    operands = [] :: [map()]
}).

-doc "Checks selected expression values against each observed enabled D, then resolves still-unknown D roots through read-first operand versions. Existing publication-resolved writes keep their producer. Capture events/times/accesses and stored versions are unchanged; only unknown transient roots, new read lanes and new events are added. Mismatched known values reject. Unrepresented small state and unsupported expressions remain explicit roots. Work is bounded by one million added events/versions/operand rows and the evaluator's plan limits.".
-spec attach(xls_protocol_spacetime:plan(), hls_spacetime_trace:trace(), hls_spacetime:bundle()) ->
    #{bundle := hls_spacetime:bundle(), ancestry := observation()}.
attach(
    #{dependencies := Dependencies, signals := Signals, registers := Registers},
    Trace,
    Bundle = #{
        events := Events,
        versions := Versions,
        resources := Resources,
        capture := Capture = #{incarnations := Epochs, observers := Observers}
    }
) ->
    Writes = [E || E = #{access := #{kind := write}} <- Events],
    Cycles = lists:foldl(
        fun(E = #{cycle := C}, A) ->
            maps:update_with(C, fun(Es) -> [E | Es] end, [E], A)
        end,
        #{},
        Writes
    ),
    Roots = maps:from_list([
        {{Inc, Resource}, Id}
     || #{
            id := Id,
            producer := root,
            incarnation := Inc,
            storage := #{resource := Resource, address := 0}
        } <- Versions
    ]),
    Initial = #state{
        plan = Dependencies,
        names = maps:from_list([{maps:get(name, S), maps:get(id, S)} || S <- Signals]),
        registers = maps:from_list([{maps:get(name, R), R} || R <- Registers]),
        cycles = Cycles,
        roots = Roots,
        epochs = Epochs,
        resources = maps:from_list([{maps:get(id, R), R} || R <- Resources]),
        versions = maps:from_list([{maps:get(id, V), V} || V <- Versions])
    },
    Final = hls_spacetime_trace:fold(fun sample/3, Initial, Trace),
    Evidence =
        <<"Selected scalar XLS operational operands checked against observed D values. Read masks describe selected expression operands and selector controls, not sensitized gate activity. Unknown expressions, scalar state without storage histories and external inputs remain roots.">>,
    Observer = #{
        id => <<"dependencies">>,
        first_sequence => 0,
        next_sequence => Final#state.sequence,
        gaps => [],
        scope => Evidence
    },
    Refined = Bundle#{
        events := Events ++ lists:reverse(Final#state.events),
        versions := [maps:get(maps:get(id, V), Final#state.versions) || V <- Versions] ++
            lists:reverse(Final#state.added_versions),
        resources := [maps:get(maps:get(id, R), Final#state.resources) || R <- Resources],
        capture := Capture#{observers := Observers ++ [Observer]}
    },
    #{
        bundle => Refined,
        ancestry => #{
            schema => 1,
            writes => Final#state.writes,
            values_checked => Final#state.checked,
            values_unknown => Final#state.unknown,
            refined => Final#state.refined,
            reads => Final#state.reads,
            operands => lists:reverse(Final#state.operands),
            evidence => Evidence
        }
    }.

%% Every computation at one sampled edge reads the same old state, regardless of write order.
-spec sample(non_neg_integer(), map(), #state{}) -> #state{}.
sample(Cycle, Values, S0 = #state{epochs = Epochs, roots = Roots, incarnation = Previous}) ->
    [Inc] = [
        I
     || #{id := I, first_cycle := First, end_cycle := End} <- Epochs,
        Cycle >= First,
        Cycle < End
    ],
    S1 =
        case Inc =:= Previous of
            true ->
                S0;
            false ->
                S0#state{
                    incarnation = Inc,
                    current = maps:from_list([
                        {R, V}
                     || {{I, R}, V} <- maps:to_list(Roots), I =:= Inc
                    ])
                }
        end,
    Writes = lists:reverse(maps:get(Cycle, S1#state.cycles, [])),
    case Writes of
        [] ->
            S1;
        _ ->
            Named = maps:map(fun(_, Id) -> maps:get(Id, Values) end, S1#state.names),
            Evaluated = xls_protocol_spacetime_dependencies:sample(S1#state.plan, Named),
            S2 = lists:foldl(fun(E, S) -> write(E, Named, Evaluated, S) end, S1, Writes),
            Current = lists:foldl(
                fun(#{access := #{resource := R, after_version := V}}, A) ->
                    A#{R => V}
                end,
                S2#state.current,
                Writes
            ),
            S2#state{current = Current}
    end.

%% A known numerical result is checked even when publication ownership already explains the write.
-spec write(hls_spacetime:event(), map(), term(), #state{}) -> #state{}.
write(
    E = #{
        id := Id,
        inputs := Inputs,
        access := #{resource := <<"register/", Name/binary>>}
    },
    Named,
    Sample,
    S0
) ->
    #{data := Data} = maps:get(Name, S0#state.registers),
    Result =
        #{value := Value} = xls_protocol_spacetime_dependencies:write(S0#state.plan, Name, Sample),
    S1 =
        case Value of
            unknown ->
                S0#state{unknown = S0#state.unknown + 1};
            _ ->
                Actual = maps:get(Data, Named),
                case Value =:= Actual of
                    true -> S0#state{checked = S0#state.checked + 1};
                    false -> error({spacetime_expression_value, Id, Name, Value, Actual})
                end
        end,
    S2 = S1#state{writes = S1#state.writes + 1},
    case
        [
            V
         || V <- Inputs,
            #{producer := root, origin := unknown, storage := null} <- [
                maps:get(V, S2#state.versions)
            ]
        ]
    of
        [Root] -> refine(E, Root, Result, S2);
        [] -> S2;
        Other -> error({spacetime_expression_roots, Id, Other})
    end.

%% Data and selector masks remain distinct in the sidecar; both are required operational inputs.
-spec refine(hls_spacetime:event(), binary(), map(), #state{}) -> #state{}.
refine(
    E = #{id := Write},
    Root,
    Result = #{data_masks := Data, control_masks := Controls, unknown := Unknown},
    S0
) ->
    Masks = maps:fold(
        fun(Name, Mask, A) ->
            maps:update_with(Name, fun(Old) -> Old bor Mask end, Mask, A)
        end,
        Data,
        Controls
    ),
    {Inputs, S1} = lists:foldl(
        fun({Name, Mask}, {Vs, S}) ->
            {V, Next} = operand(E, Name, Mask, S),
            {[V | Vs], Next}
        end,
        {[], S0},
        lists:sort(maps:to_list(Masks))
    ),
    {AllInputs, S2} =
        case Unknown of
            [] ->
                {Inputs, S1};
            _ ->
                {V, Sx} = unknown(
                    E,
                    <<"unresolved">>,
                    iolist_to_binary(
                        io_lib:format("Unsupported or missing scalar operands: ~p", [Unknown])
                    ),
                    S1
                ),
                {[V | Inputs], Sx}
        end,
    Id = <<"dependency/", Write/binary>>,
    Evidence =
        <<"Runtime-selected scalar expression operands; known D results checked exactly. Selector inputs remain required controls; no sensitized gate-path claim.">>,
    Computation = event(
        Id, E, <<"register_compute">>, lists:reverse(AllInputs), [Root], Evidence, S2
    ),
    Version = maps:get(Root, S2#state.versions),
    S3 = append(Computation, S2),
    S4 = record(S3),
    S4#state{
        versions = (S4#state.versions)#{
            Root := Version#{producer := Id, origin := event, evidence := Evidence}
        },
        refined = S4#state.refined + 1,
        operands = [
            #{
                event => Id,
                write => Write,
                data_masks => wire_masks(Data),
                control_masks => wire_masks(Controls),
                unknown => Unknown,
                value_checked => maps:get(value, Result) =/= unknown
            }
            | S4#state.operands
        ]
    }.

%% Only represented register words can produce storage-read versions; other leaves remain roots.
-spec operand(hls_spacetime:event(), binary(), pos_integer(), #state{}) -> {binary(), #state{}}.
operand(E = #{id := Write}, Name, Mask, S0) ->
    Resource = <<"register/", Name/binary>>,
    case {maps:find(Resource, S0#state.resources), maps:find(Resource, S0#state.current)} of
        {{ok, #{width := Width, ports := Ports} = R}, {ok, Word}} ->
            true = Mask > 0 andalso Mask < (1 bsl Width),
            Port = <<"read/dependency/", (maps:get(actor, E))/binary>>,
            Request = <<"dependency/read/", Write/binary, "/", Name/binary>>,
            Response = <<Request/binary, "/result">>,
            Value = <<Response/binary, "/value">>,
            Access = #{
                kind => read_request,
                resource => Resource,
                address => 0,
                port => Port,
                version => Word,
                read_mask => Mask
            },
            Read = event(
                Request,
                E,
                <<"selected_operand_read">>,
                [Word],
                [],
                <<"Runtime-selected operational bits of the current encoded pre-edge register word">>,
                S0
            ),
            S1 = append(Read#{access => Access}, S0),
            Return = event(
                Response,
                E,
                <<"selected_operand_value">>,
                [Word],
                [Value],
                <<"Zero-latency read result; same selected mask and pre-edge version as request">>,
                S1
            ),
            S2 = append(Return#{access => Access#{kind := read_result, request => Request}}, S1),
            V = version(
                Value, Response, event, E, <<"Transient selected encoded-register operand">>
            ),
            S3 = add_version(V, S2),
            {Value, S3#state{
                reads = S3#state.reads + 1,
                resources = (S3#state.resources)#{Resource := R#{ports := Ports#{Port => read}}}
            }};
        _ ->
            unknown(
                E,
                Name,
                iolist_to_binary(
                    io_lib:format(
                        "Selected scalar ~s bits ~.16B lack a represented storage history; external input or omitted small/reencoded state",
                        [Name, Mask]
                    )
                ),
                S0
            )
    end.

%% Unknown roots carry source identity, not a guessed storage version or nearest event.
-spec unknown(hls_spacetime:event(), binary(), binary(), #state{}) -> {binary(), #state{}}.
unknown(E = #{id := Write}, Name, Evidence, S) ->
    Id = <<"dependency/root/", Write/binary, "/", Name/binary>>,
    V = version(Id, root, unknown, E, Evidence),
    {Id, add_version(V, S)}.

%% New records share the consumer's task/activation but have their own bounded observer sequence.
-spec event(binary(), hls_spacetime:event(), binary(), [binary()], [binary()], binary(), #state{}) ->
    hls_spacetime:event().
event(Id, E, Operation, Inputs, Outputs, Evidence, S) ->
    #{
        id => Id,
        observer => <<"dependencies">>,
        sequence => S#state.sequence,
        cycle => maps:get(cycle, E),
        incarnation => maps:get(incarnation, E),
        actor => maps:get(actor, E),
        task => maps:get(task, E),
        activation => maps:get(activation, E),
        operation => Operation,
        inputs => Inputs,
        outputs => Outputs,
        evidence => Evidence
    }.

%% Transient versions have no storage address; reads establish their stored-word provenance.
-spec version(binary(), root | binary(), unknown | event, hls_spacetime:event(), binary()) ->
    hls_spacetime:version().
version(Id, Producer, Origin, E, Evidence) ->
    #{
        id => Id,
        producer => Producer,
        origin => Origin,
        incarnation => maps:get(incarnation, E),
        storage => null,
        evidence => Evidence
    }.

%% The extra observer cannot silently exceed the recording's declared finite-size discipline.
-spec append(hls_spacetime:event(), #state{}) -> #state{}.
append(E, S = #state{sequence = N, events = Events}) ->
    Counted = record(S),
    Counted#state{sequence = N + 1, events = [E | Events]}.

%% Unknown leaves and sidecar rows consume the same finite budget as visible events.
-spec record(#state{}) -> #state{}.
record(S = #state{records = N}) when N < 1000000 -> S#state{records = N + 1};
record(_) -> error(spacetime_dependency_record_limit).

%% Count before retaining each transient or unknown version.
-spec add_version(hls_spacetime:version(), #state{}) -> #state{}.
add_version(V, S) ->
    Counted = record(S),
    Counted#state{added_versions = [V | Counted#state.added_versions]}.

%% Sidecar masks share the graph's exact wide-integer JSON convention.
-spec wire_masks(#{binary() => non_neg_integer()}) -> #{binary() => binary()}.
wire_masks(Masks) ->
    maps:map(fun(_, Mask) -> <<"0x", (integer_to_binary(Mask, 16))/binary>> end, Masks).
