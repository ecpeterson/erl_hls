-module(xls_protocol_spacetime_capture).
-moduledoc "Converts passive source-protocol samples into cycle events and encoded register histories. The tap planner owns signal meaning; this adapter records handshakes and actual enables, qualifies adjacent register transfers, then joins publication ownership and selected scalar operands. Unsupported numerical ancestry stays explicit. It does not interpret narrowed values using source bit offsets.".

%% Offline capture conversion; file ownership remains with the caller.
-export([capture/3, bundle/3]).
-export_type([capture/0]).

-doc "Generic event graph and separate stream, publication and scalar-operand evidence from one exact capture.".
-type capture() :: #{
    bundle := hls_spacetime:bundle(),
    stream := xls_protocol_spacetime_stream:observation(),
    publication => xls_protocol_spacetime_publication:observation(),
    ancestry => xls_protocol_spacetime_ancestry:observation()
}.

%% Lists are accumulated backwards; current storage is immutable within a sampled edge.
-record(state, {
    plan :: map(),
    registers :: [map()],
    by_name :: map(),
    by_path :: map(),
    logical = #{} :: map(),
    events = [] :: [map()],
    versions = [] :: [map()],
    relations = [] :: [map()],
    current = #{} :: map(),
    pending = #{} :: map(),
    leases = #{} :: map(),
    expected = #{} :: map(),
    sequence = 0 :: non_neg_integer(),
    unique = 0 :: non_neg_integer(),
    incarnation = 0 :: non_neg_integer(),
    first = 0 :: non_neg_integer(),
    incarnations = [] :: [map()],
    reset = false :: boolean(),
    warm = false :: boolean()
}).

-doc "Returns only the validated generic graph from capture/3. Stream dependency events remain in the graph; backend frame identities and pending/reset diagnostics are available separately through capture/3.".
-spec bundle(xls_protocol_spacetime:plan(), hls_spacetime_trace:trace(), hls_spacetime:build()) ->
    hls_spacetime:bundle().
bundle(Plan, Trace, Build) ->
    #{bundle := Bundle} = capture(Plan, Trace, Build),
    Bundle.

-doc "Builds a validated simulation-witness graph plus separate backend evidence sidecars from the native tap plan, a complete or explicitly incomplete bounded trace, and exact build identities. Records enabled writes to retained data registers of at least 16 bits, semantic receiver/publication events, link ownership transitions and observed stream transfers. Checks each adjacent nonreset Q/D/enable transfer. Selected scalar values are checked against observed D; publication occurrence identities follow checked ownership controls. The final enabled edge lacks a following Q sample. Unsupported expressions and unrepresented controls remain unknown roots. Plans without stream taps produce an empty stream sidecar with an explicit unobserved scope.".
-spec capture(xls_protocol_spacetime:plan(), hls_spacetime_trace:trace(), hls_spacetime:build()) ->
    capture().
capture(Plan = #{signals := Signals, registers := Registers, state := Leaves}, Trace, Build) ->
    [] = maps:get(unsupported, Plan),
    ok = check_build(Plan, Build),
    ok = check_taps(Signals, maps:get(signals, Trace)),
    [] = [
        R
     || R = #{width := W, rule := Rule} <- Registers,
        W >= 16,
        Rule =/= enabled_same_edge_register_write
    ],
    Data = [R || R = #{width := W, rule := enabled_same_edge_register_write} <- Registers, W >= 16],
    ByName = maps:from_list([{maps:get(name, S), maps:get(id, S)} || S <- Signals]),
    ByPath = maps:from_list([{maps:get(tuple_path, L), L} || L <- Leaves]),
    ok = check_owner_encodings(Plan, ByPath),
    Logic = logical_resources(Plan),
    Initial = #state{
        plan = Plan,
        registers = Data,
        by_name = ByName,
        by_path = ByPath,
        logical = maps:from_list([{maps:get(id, R), true} || R <- Logic])
    },
    Final = hls_spacetime_trace:fold(fun sample/3, Initial, Trace),
    End = maps:get(end_cycle, Trace),
    true = End > 0,
    Incarnations = lists:reverse([
        epoch(Final#state.incarnation, Final#state.first, End) | Final#state.incarnations
    ]),
    Scope = capture_scope(Plan),
    Result = #{
        format => spacetime,
        schema => 1,
        unit => cycle,
        evidence => simulation_witness,
        build => Build,
        capture => #{
            device => <<"board">>,
            clock => <<"clk">>,
            first_cycle => 0,
            end_cycle => End,
            complete => maps:get(complete, Trace),
            evidence => Scope,
            incarnations => Incarnations,
            observers => [
                #{
                    id => <<"protocol">>,
                    first_sequence => 0,
                    next_sequence => Final#state.sequence,
                    gaps => [],
                    scope => Scope
                }
            ]
        },
        resources => [resource(R, Plan) || R <- Data] ++ Logic,
        versions => lists:reverse(Final#state.versions),
        events => lists:reverse(Final#state.events),
        relations => lists:reverse(Final#state.relations),
        activity => [],
        physical => null
    },
    Observed =
        #{bundle := Joined} =
        case maps:find(stream, Plan) of
            {ok, Stream} ->
                xls_protocol_spacetime_stream:attach(Stream, Trace, Result);
            error ->
                #{
                    bundle => Result,
                    stream => #{
                        schema => 1,
                        frames => [],
                        pending => [],
                        partial => null,
                        retired => [],
                        evidence => <<"Stream observations absent from this tap plan">>
                    }
                }
        end,
    WithPublication =
        case maps:find(publication, Plan) of
            {ok, Publication} ->
                #{bundle := Published, publication := PublicationEvidence} =
                    xls_protocol_spacetime_publication:attach(Publication, Trace, Joined),
                Observed#{bundle := Published, publication => PublicationEvidence};
            error ->
                Observed
        end,
    FinalCapture =
        case maps:is_key(dependencies, Plan) of
            true ->
                #{bundle := Computed, ancestry := Ancestry} =
                    xls_protocol_spacetime_ancestry:attach(
                        Plan, Trace, maps:get(bundle, WithPublication)
                    ),
                WithPublication#{bundle := Computed, ancestry => Ancestry};
            false ->
                WithPublication
        end,
    _ = hls_spacetime:validate(maps:get(bundle, FinalCapture)),
    FinalCapture.

%% Storage-only selection makes its intentionally absent semantic observations explicit.
-spec capture_scope(xls_protocol_spacetime:plan()) -> binary().
capture_scope(#{observation_scope := storage}) ->
    <<"Storage-only recording: enabled writes to retained RTL data registers >=16 bits and adjacent Q/D/enable checks. No actor, publication, stream or selected-operand attribution. D producers remain unknown; unavailable controls are retained in the preparation. Final enabled edge has no following Q sample.">>;
capture_scope(_) ->
    <<"All sampled enabled writes to retained RTL data registers >=16 bits; receiver accept/head_done/take/postpone/phase and publication controls; link ownership transitions. Encoded register operands only; unresolved computation inputs are explicit unknown roots. No sensitized gate ancestry. Adjacent Q/D/enable transfers checked; final enabled edge has no following Q sample.">>.

%% Exact source, RTL and native observation-plan digests jointly identify this interpretation.
-spec check_build(xls_protocol_spacetime:plan(), hls_spacetime:build()) -> ok.
check_build(Plan = #{inputs := #{rtl := Rtl, source_build := Source}}, Build) ->
    Observation = xls_protocol_spacetime:observation_digest(Plan),
    lists:foreach(
        fun({Key, Expected}) ->
            case maps:find(Key, Build) of
                {ok, Expected} -> ok;
                Other -> error({spacetime_build_binding, Key, Expected, Other})
            end
        end,
        [{rtl, Rtl}, {source, Source}, {observation, Observation}]
    ).

%% The ownership-code interpretation requires each declared capture's original two bits.
-spec check_owner_encodings(xls_protocol_spacetime:plan(), map()) -> ok.
check_owner_encodings(#{actors := Actors}, Paths) ->
    N = length(Actors),
    Slots = lists:usort([
        {maps:get(<<"link">>, Slot), maps:get(<<"slot">>, Slot)}
     || #{inbox := Inbox} <- Actors, Slot <- maps:get(<<"slots">>, Inbox)
    ]),
    lists:foreach(
        fun({Link, Slot}) ->
            Path = [0, 0, N + Link, Slot, 0],
            case maps:find(Path, Paths) of
                {ok, #{source_width := 2, physical_width := 2, signal := Name}} when
                    is_binary(Name), byte_size(Name) > 0
                ->
                    ok;
                Other ->
                    error({unsupported_owner_encoding, Path, Other})
            end
        end,
        Slots
    ).

%% A trace from another declaration set is not interchangeable with this semantic plan.
-spec check_taps([map()], [map()]) -> ok.
check_taps(Planned, Observed) ->
    ById = maps:from_list([{maps:get(id, S), maps:with([width, path], S)} || S <- Observed]),
    lists:foreach(
        fun(#{id := Id} = S) ->
            Expected = maps:with([width, path], S),
            case maps:find(Id, ById) of
                {ok, Expected} -> ok;
                Other -> error({spacetime_tap_binding, Id, Expected, Other})
            end
        end,
        Planned
    ).

%% Reset assertion retires ownership; initializer cycles cannot accept source heads.
-spec sample(non_neg_integer(), map(), #state{}) -> #state{}.
sample(Cycle, Values, S0) ->
    S1 = verify_previous(Values, S0),
    Reset = maps:get(<<"reset">>, Values) =/= 0,
    case value(<<"input_reset">>, Values, S1) =/= 0 of
        Reset -> ok;
        Other -> error({spacetime_reset_binding, Cycle, Reset, Other})
    end,
    S2 =
        case Reset andalso not S1#state.reset andalso Cycle > 0 of
            true ->
                S1#state{
                    incarnation = S1#state.incarnation + 1,
                    first = Cycle,
                    current = #{},
                    pending = #{},
                    leases = #{},
                    incarnations = [
                        epoch(S1#state.incarnation, S1#state.first, Cycle) | S1#state.incarnations
                    ]
                };
            false ->
                S1
        end,
    Active = not Reset andalso value(<<"p0_stage_done">>, Values, S2) =/= 0,
    S3 =
        case Active andalso S2#state.warm of
            true -> semantic(Cycle, Values, link_events(Cycle, Values, S2));
            false -> S2
        end,
    S4 =
        case Reset of
            false ->
                lists:foldl(
                    fun(R, S) -> write_register(Cycle, Values, R, S) end, S3, S3#state.registers
                );
            true ->
                S3
        end,
    Expected =
        case Reset of
            true ->
                #{};
            false ->
                maps:from_list([
                    {maps:get(name, R), next_value(R, Values, S4)}
                 || R <- S4#state.registers
                ])
        end,
    S4#state{
        expected = Expected, reset = Reset, warm = not Reset andalso (Active orelse S2#state.warm)
    }.

%% Every recorded prior register transfer must agree with the next observed Q.
-spec verify_previous(map(), #state{}) -> #state{}.
verify_previous(Values, S = #state{expected = Expected}) ->
    maps:foreach(
        fun(Name, ExpectedValue) ->
            Actual = value(Name, Values, S),
            case Actual =:= ExpectedValue of
                true -> ok;
                false -> error({spacetime_register_transfer, Name, ExpectedValue, Actual})
            end
        end,
        Expected
    ),
    S.

%% Use actual emitted enables rather than value-change detection.
-spec next_value(map(), map(), #state{}) -> non_neg_integer().
next_value(#{name := Name, enable := Enable, data := Data}, Values, S) ->
    value(
        case value(Enable, Values, S) of
            0 -> Name;
            _ -> Data
        end,
        Values,
        S
    ).

%% A full encoded-register write has a new identity, even if D equals Q.
-spec write_register(non_neg_integer(), map(), map(), #state{}) -> #state{}.
write_register(Cycle, Values, #{name := Name, width := Width, enable := Enable}, S0) ->
    case value(Enable, Values, S0) of
        0 ->
            S0;
        _ ->
            {Before, S1} = current(Name, S0),
            {Unknown, S2} = root(
                null,
                unknown,
                <<"Enabled register D observed; numerical contributors are not yet attributed">>,
                S1
            ),
            {Id, S3} = fresh(<<"e">>, S2),
            {After, S4} = fresh(<<"v">>, S3),
            Actor = <<"register/", Name/binary>>,
            E = event(
                Id,
                Cycle,
                Actor,
                Id,
                <<"register_write">>,
                [Unknown],
                [After],
                <<"Actual emitted load enable; full encoded word, including equal-valued writes">>,
                S4
            ),
            Access = #{
                kind => write,
                resource => register_id(Name),
                address => 0,
                port => <<"w">>,
                before => Before,
                after_version => After,
                mask => (1 bsl Width) - 1
            },
            S5 = append(E#{access => Access}, S4),
            V = version(
                After,
                Id,
                event,
                #{resource => register_id(Name), address => 0},
                <<"Observed D value committed by the emitted enable">>,
                S5
            ),
            S5#state{
                versions = [V | S5#state.versions], current = (S5#state.current)#{Name => After}
            }
    end.

%% Receiver controls are observations of committed transitions, never pure preview invocations.
-spec semantic(non_neg_integer(), map(), #state{}) -> #state{}.
semantic(Cycle, Values, S = #state{plan = #{actors := Actors}}) ->
    lists:foldl(fun(A, Acc) -> actor_events(Cycle, Values, A, Acc) end, S, Actors).

%% Preserve one admitted head until its own completion or reset; publication owns older work.
-spec actor_events(non_neg_integer(), map(), map(), #state{}) -> #state{}.
actor_events(Cycle, Values, #{actor := I, inbox := Inbox}, S0) ->
    Actor = actor_id(I),
    S1 =
        case control(I, <<"accept">>, Values) of
            0 ->
                S0;
            _ ->
                false = maps:is_key(I, S0#state.pending),
                {AcceptedActivation, A0} = fresh(<<"activation">>, S0),
                {Machine, A1} = read_path(Cycle, [0, I + 1, 0, 0], Actor, AcceptedActivation, A0),
                Mask = control(I, <<"reservation">>, Values),
                {Message, A2} = message_read(Cycle, I, Inbox, Mask, Actor, AcceptedActivation, A1),
                {AcceptedToken, A3} = action(
                    Cycle, Actor, AcceptedActivation, <<"accept">>, [Machine, Message], A2
                ),
                A3#state{
                    pending = (A3#state.pending)#{
                        I => #{
                            activation => AcceptedActivation, token => AcceptedToken, mask => Mask
                        }
                    }
                }
        end,
    Waiting = wait_event(Cycle, I, Values, S1),
    Retiring = lists:any(
        fun(Meaning) -> control(I, Meaning, Values) =/= 0 end,
        [<<"phase_boundary">>, <<"head_done">>, <<"take">>, <<"postpone">>]
    ),
    S5 =
        case Retiring of
            true -> retirement_events(Cycle, I, Values, Waiting);
            false -> Waiting
        end,
    case control(I, <<"publication_accept">>, Values) of
        0 ->
            S5;
        _ ->
            {Publication, P0} = fresh(<<"publication">>, S5),
            {Payload, P1} = read_path(Cycle, [0, I + 1, 0, 5, 0], Actor, Publication, P0),
            {Other, P2} = root(
                null,
                unknown,
                <<"Publication layout/control contributors are outside represented data-register reads">>,
                P1
            ),
            element(
                2, action(Cycle, Actor, Publication, <<"publication_accept">>, [Payload, Other], P2)
            )
    end.

%% Only a registered selected action can wait; a pure blocked candidate is not work.
-spec wait_event(non_neg_integer(), non_neg_integer(), map(), #state{}) -> #state{}.
wait_event(Cycle, I, Values, S = #state{pending = Pending}) ->
    Waiting =
        control(I, <<"egress_blocked">>, Values) =/= 0 andalso
            flag([0, I + 1, 0, 2], Values, S) andalso flag([0, I + 1, 0, 3], Values, S),
    case {Waiting, maps:find(I, Pending)} of
        {true, {ok, #{activation := Activation, token := Previous} = Head}} ->
            0 = control(I, <<"head_done">>, Values),
            {Unknown, S1} = root(
                null,
                unknown,
                <<"Registered selected action is blocked; occupying publication ancestry is not joined">>,
                S
            ),
            {Token, S2} = action(
                Cycle, actor_id(I), Activation, <<"entry_wait">>, [Previous, Unknown], S1
            ),
            S2#state{pending = Pending#{I => Head#{token := Token}}};
        _ ->
            S
    end.

%% Boolean source fields must survive with their exact one-bit encoding.
-spec flag([non_neg_integer()], map(), #state{}) -> boolean().
flag(Path, Values, S = #state{by_path = Paths}) ->
    #{signal := Name, source_width := 1, physical_width := 1} = maps:get(Path, Paths),
    true = Name =/= null,
    value(Name, Values, S) =/= 0.

%% Completion/phase observations use an admitted-head identity only while its reservation is live.
-spec retirement_events(non_neg_integer(), non_neg_integer(), map(), #state{}) -> #state{}.
retirement_events(Cycle, I, Values, S1) ->
    Actor = actor_id(I),
    {Activation, Input, S2} = activation_input(I, S1),
    S3 =
        case control(I, <<"phase_boundary">>, Values) of
            0 -> S2;
            _ -> element(2, action(Cycle, Actor, Activation, <<"phase_boundary">>, [Input], S2))
        end,
    {DoneToken, S4} =
        case control(I, <<"head_done">>, Values) of
            0 ->
                {none, S3};
            _ ->
                {Token, B} = action(Cycle, Actor, Activation, <<"head_done">>, [Input], S3),
                {Token, B#state{pending = maps:remove(I, B#state.pending)}}
        end,
    lists:foldl(
        fun(Meaning, Acc) ->
            case control(I, Meaning, Values) of
                0 ->
                    Acc;
                _ ->
                    case DoneToken of
                        none -> error({retirement_without_completion, I, Meaning});
                        _ -> element(2, action(Cycle, Actor, Activation, Meaning, [DoneToken], Acc))
                    end
            end
        end,
        S4,
        [<<"take">>, <<"postpone">>]
    ).

%% Root unmatched internal work explicitly instead of attaching the most recent unrelated activation.
-spec activation_input(non_neg_integer(), #state{}) -> {binary(), binary(), #state{}}.
activation_input(I, S = #state{pending = Pending}) ->
    case maps:find(I, Pending) of
        {ok, #{activation := Activation, token := Token}} ->
            {Activation, Token, S};
        error ->
            {Activation, S1} = fresh(<<"internal">>, S),
            {Token, S2} = root(
                null,
                unknown,
                <<"No retained admitted-head activation for this internal transition">>,
                S1
            ),
            {Activation, Token, S2}
    end.

%% Select exactly one receiver-local mailbox slot; startup/host cases have explicit origins.
-spec message_read(
    non_neg_integer(), non_neg_integer(), map(), non_neg_integer(), binary(), binary(), #state{}
) -> {binary(), #state{}}.
message_read(Cycle, _I, Inbox, Mask, Actor, Activation, S) ->
    true = Mask > 0 andalso (Mask band (Mask - 1)) =:= 0,
    Index = bit_index(Mask, 0),
    case [Slot || Slot = #{<<"index">> := K} <- maps:get(<<"slots">>, Inbox), K =:= Index] of
        [#{<<"link">> := Link, <<"slot">> := Slot}] ->
            N = length(maps:get(actors, S#state.plan)),
            read_path(Cycle, [0, 0, N + Link, Slot, 1], Actor, Activation, S);
        [] ->
            #{
                <<"host">> := #{<<"offset">> := HostOffset, <<"slots">> := HostSlots},
                <<"startup">> := #{<<"offset">> := StartupOffset, <<"count">> := StartupCount}
            } = Inbox,
            case Index >= HostOffset andalso Index < HostOffset + HostSlots of
                true ->
                    N = length(maps:get(actors, S#state.plan)),
                    read_path(Cycle, [0, N + 1, 0], Actor, Activation, S);
                false ->
                    true = Index >= StartupOffset andalso Index < StartupOffset + StartupCount,
                    root(
                        null,
                        initial,
                        <<"Declared immutable startup frame selected by its receiver-local slot">>,
                        S
                    )
            end
    end.

%% Read current encoded storage through a separate read lane, before same-edge writes.
-spec read_path(non_neg_integer(), [non_neg_integer()], binary(), binary(), #state{}) ->
    {binary(), #state{}}.
read_path(Cycle, Path, Actor, Activation, S = #state{by_path = Paths}) ->
    case maps:get(Path, Paths) of
        #{signal := Name, physical_width := W} when Name =/= null, W >= 16 ->
            read_register(Cycle, Name, Actor, Activation, S);
        _ ->
            root(
                null,
                unknown,
                <<"Required source value was eliminated/reencoded without a supported register observation">>,
                S
            )
    end.

%% Zero-latency request/result pairs retain the selected version despite later overwrites.
-spec read_register(non_neg_integer(), binary(), binary(), binary(), #state{}) ->
    {binary(), #state{}}.
read_register(Cycle, Name, Actor, Activation, S0) ->
    {Word, S1} = current(Name, S0),
    {Request, S2} = fresh(<<"e">>, S1),
    Access = #{
        kind => read_request,
        resource => register_id(Name),
        address => 0,
        port => read_port(Actor),
        version => Word
    },
    E = event(
        Request,
        Cycle,
        Actor,
        Activation,
        <<"operand_read">>,
        [Word],
        [],
        <<"Observed receiver/publication operation reads this retained encoded register">>,
        S2
    ),
    S3 = append(E#{access => Access}, S2),
    {Response, S4} = fresh(<<"e">>, S3),
    {Value, S5} = fresh(<<"v">>, S4),
    R = event(
        Response,
        Cycle,
        Actor,
        Activation,
        <<"operand_value">>,
        [Word],
        [Value],
        <<"Same-edge combinational register read, before writes">>,
        S5
    ),
    S6 = append(R#{access => Access#{kind => read_result, request => Request}}, S5),
    V = version(
        Value,
        Response,
        event,
        null,
        <<"Transient snapshot of the selected current encoded word">>,
        S6
    ),
    {Value, S6#state{versions = [V | S6#state.versions]}}.

%% Capture leases have non-overlapping old/new owner codes; payload equality does not identify messages.
-spec link_events(non_neg_integer(), map(), #state{}) -> #state{}.
link_events(
    Cycle, Values, S = #state{plan = #{actors := Actors, registers := Regs}, by_path = Paths}
) ->
    N = length(Actors),
    ByReg = maps:from_list([{maps:get(name, R), R} || R <- Regs]),
    Slots = lists:usort([
        {maps:get(<<"link">>, Slot), maps:get(<<"slot">>, Slot)}
     || #{inbox := Inbox} <- Actors, Slot <- maps:get(<<"slots">>, Inbox)
    ]),
    lists:foldl(
        fun
            (
                {[0, 0, Component, Slot, 0], #{
                    signal := Name, source_width := 2, physical_width := 2
                }},
                Acc
            ) when
                Component >= N, Name =/= null
            ->
                Key = {Component - N, Slot},
                case lists:member(Key, Slots) of
                    false ->
                        Acc;
                    true ->
                        R = maps:get(Name, ByReg),
                        Old = value(Name, Values, Acc),
                        New = next_value(R, Values, Acc),
                        Operation =
                            case {Old, New} of
                                {0, 1} -> <<"arrival">>;
                                {1, 2} -> <<"acquire">>;
                                {2, 0} -> <<"release">>;
                                {X, X} -> none;
                                _ -> error({capture_owner_transition, Name, Old, New})
                            end,
                        case Operation of
                            none -> Acc;
                            _ -> link_event(Cycle, Key, Operation, Acc)
                        end
                end;
            (_, Acc) ->
                Acc
        end,
        S,
        lists:sort(maps:to_list(Paths))
    ).

%% Capture ownership orders one lease; an arrival's publication lineage remains unknown.
-spec link_event(non_neg_integer(), {non_neg_integer(), non_neg_integer()}, binary(), #state{}) ->
    #state{}.
link_event(Cycle, Key = {Link, Slot}, Operation, S0) ->
    {Activation, Input, S1} =
        case {Operation, maps:find(Key, S0#state.leases)} of
            {<<"arrival">>, error} ->
                {A, Sx} = fresh(<<"lease">>, S0),
                {V, Sy} = root(
                    null,
                    unknown,
                    <<"Exact capture arrival; source publication lineage has not been joined">>,
                    Sx
                ),
                {A, V, Sy};
            {<<"arrival">>, {ok, _}} ->
                error({capture_arrival_while_owned, Key});
            {_, {ok, #{activation := A, token := V}}} ->
                {A, V, S0};
            {_, error} ->
                {A, Sx} = fresh(<<"lease">>, S0),
                {V, Sy} = root(
                    null,
                    unknown,
                    <<"Capture ownership already existed when this observation scope began">>,
                    Sx
                ),
                {A, V, Sy}
        end,
    Actor = iolist_to_binary(["link/", integer_to_binary(Link), "/", integer_to_binary(Slot)]),
    {Token, S2} = action(Cycle, Actor, Activation, Operation, [Input], S1),
    Leases =
        case Operation of
            <<"release">> -> maps:remove(Key, S2#state.leases);
            _ -> (S2#state.leases)#{Key => #{activation => Activation, token => Token}}
        end,
    S2#state{leases = Leases}.

%% One event occurrence creates one token, even if all observed payload bits repeat.
-spec action(non_neg_integer(), binary(), binary(), binary(), [binary()], #state{}) ->
    {binary(), #state{}}.
action(Cycle, Actor, Activation, Operation, Inputs, S0) ->
    {Id, S1} = fresh(<<"e">>, S0),
    {Token, S2} = fresh(<<"v">>, S1),
    E = event(
        Id,
        Cycle,
        Actor,
        Activation,
        Operation,
        Inputs,
        [Token],
        <<"Accepted source-protocol control occurrence; token records occurrence, not payload bits">>,
        S2
    ),
    S3 = append(E, S2),
    V = version(Token, Id, event, null, <<"Distinct control occurrence">>, S3),
    {Token, S3#state{versions = [V | S3#state.versions]}}.

%% Roots appear only when a word is first accessed in the current incarnation.
-spec current(binary(), #state{}) -> {binary(), #state{}}.
current(Name, S = #state{current = Current}) ->
    case maps:find(Name, Current) of
        {ok, V} ->
            {V, S};
        error ->
            {V, S1} = root(
                #{resource => register_id(Name), address => 0},
                unknown,
                <<"First observed encoded word in this reset incarnation">>,
                S
            ),
            {V, S1#state{current = Current#{Name => V}}}
    end.

%% Unknown provenance is visible as a named root rather than invented edges.
-spec root(null | map(), initial | unknown, binary(), #state{}) -> {binary(), #state{}}.
root(Storage, Origin, Evidence, S0) ->
    {Id, S1} = fresh(<<"v">>, S0),
    V = version(Id, root, Origin, Storage, Evidence, S1),
    {Id, S1#state{versions = [V | S1#state.versions]}}.

%% Storage and transient values share reset-incarnation identity.
-spec version(binary(), root | binary(), atom(), null | map(), binary(), #state{}) -> map().
version(Id, Producer, Origin, Storage, Evidence, S) ->
    #{
        id => Id,
        producer => Producer,
        origin => Origin,
        storage => Storage,
        evidence => Evidence,
        incarnation => incarnation_id(S#state.incarnation)
    }.

%% A task label groups protocol work without pretending to know source logical step numbers.
-spec event(
    binary(),
    non_neg_integer(),
    binary(),
    binary(),
    binary(),
    [binary()],
    [binary()],
    binary(),
    #state{}
) -> map().
event(Id, Cycle, Actor, Activation, Operation, Inputs, Outputs, Evidence, S) ->
    E = #{
        id => Id,
        observer => <<"protocol">>,
        sequence => S#state.sequence,
        cycle => Cycle,
        incarnation => incarnation_id(S#state.incarnation),
        actor => Actor,
        task => <<"source-protocol">>,
        activation => Activation,
        operation => Operation,
        inputs => Inputs,
        outputs => Outputs,
        evidence => Evidence
    },
    case maps:is_key(Actor, S#state.logical) of
        true -> E#{resources => [Actor]};
        false -> E
    end.

%% Logical control resources have no inferred placed-cell binding in this cycle artifact.
-spec logical_resources(map()) -> [map()].
logical_resources(#{actors := Actors}) ->
    Slots = lists:usort([
        {maps:get(<<"link">>, Slot), maps:get(<<"slot">>, Slot)}
     || #{inbox := Inbox} <- Actors, Slot <- maps:get(<<"slots">>, Inbox)
    ]),
    [
        #{
            id => actor_id(maps:get(actor, A)),
            kind => logic,
            evidence => <<"Retained source-protocol receiver controls; physical mapping absent">>
        }
     || A <- Actors
    ] ++
        [
            #{
                id => iolist_to_binary([
                    "link/", integer_to_binary(Link), "/", integer_to_binary(Slot)
                ]),
                kind => logic,
                evidence =>
                    <<"Declared transport capture-slot ownership control; physical mapping absent">>
            }
         || {Link, Slot} <- Slots
        ].

%% Fail before silently truncating semantic evidence.
-spec append(map(), #state{}) -> #state{}.
append(Event, S = #state{sequence = N, events = Events}) when N < 1000000 ->
    S#state{sequence = N + 1, events = [Event | Events]};
append(_, _) ->
    error(spacetime_event_limit).

%% Event, activation and version identities share a monotone nonce, not value hashes.
-spec fresh(binary(), #state{}) -> {binary(), #state{}}.
fresh(Prefix, S = #state{unique = N}) ->
    {<<Prefix/binary, "/", (integer_to_binary(N))/binary>>, S#state{unique = N + 1}}.

%% Data registers use independent observation read/write lanes and actual encoded widths.
-spec resource(map(), map()) -> map().
resource(#{name := Name, width := Width}, #{actors := Actors, state := Leaves}) ->
    Ports = maps:from_list([{read_port(actor_id(maps:get(actor, A))), read} || A <- Actors]),
    Paths = [maps:get(tuple_path, L) || L <- Leaves, maps:get(signal, L) =:= Name],
    Evidence = iolist_to_binary(
        io_lib:format(
            "Retained exact RTL register; physical encoding, not reconstructed source layout. Raw tuple paths: ~w",
            [Paths]
        )
    ),
    #{
        id => register_id(Name),
        kind => register,
        width => Width,
        depth => 1,
        ports => Ports#{<<"w">> => write},
        read_latency => 0,
        collision => read_first,
        reset => reinitialize,
        evidence => Evidence
    }.

%% Independent combinational actor readers are distinct observed lanes, not BRAM ports.
-spec read_port(binary()) -> binary().
read_port(Actor) -> <<"read/", Actor/binary>>.

%% Named taps are strict: missing input cannot become zero or false.
-spec value(binary(), map(), #state{}) -> non_neg_integer().
value(Name, Values, #state{by_name = Names}) -> maps:get(maps:get(Name, Names), Values).

%% Semantic signal IDs are generated by the tap planner.
-spec control(non_neg_integer(), binary(), map()) -> non_neg_integer().
control(I, Meaning, Values) ->
    maps:get(<<"actor/", (integer_to_binary(I))/binary, "/", Meaning/binary>>, Values).

%% One-hot selection has already been checked by the caller.
-spec bit_index(pos_integer(), non_neg_integer()) -> non_neg_integer().
bit_index(1, I) -> I;
bit_index(M, I) -> bit_index(M bsr 1, I + 1).

%% Stable semantic resource names do not imply placed-cell correspondence.
-spec register_id(binary()) -> binary().
register_id(Name) -> <<"register/", Name/binary>>.

%% Actor indices belong to the frozen network manifest.
-spec actor_id(non_neg_integer()) -> binary().
actor_id(I) -> <<"actor/", (integer_to_binary(I))/binary>>.

%% Reset boundaries partition the complete observed cycle range.
-spec incarnation_id(non_neg_integer()) -> binary().
incarnation_id(I) -> <<"reset/", (integer_to_binary(I))/binary>>.

%% Empty incarnations are never created because reset edges occur at distinct cycles.
-spec epoch(non_neg_integer(), non_neg_integer(), pos_integer()) -> map().
epoch(I, First, End) -> #{id => incarnation_id(I), first_cycle => First, end_cycle => End}.
