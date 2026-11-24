-module(hls_spacetime_feedback_fixture).
-moduledoc "Finite local3/shared3 plan, characterization and revision witness for Stage 5.".

-include_lib("eunit/include/eunit.hrl").

-export([main/0, propose/2, write/2, revise/6]).

-doc "Runs propose MODE PLAN, write PLAN BUNDLE or revise PLAN IMPLEMENTATION EVIDENCE METRICS CHARACTERIZATION REVISED for the Python witness.".
-spec main() -> no_return().
main() ->
    dispatch(init:get_plain_arguments()).

%% Dispatch only the closed test command vocabulary supplied after `-extra`.
-spec dispatch([string()]) -> no_return().
dispatch(["propose", Mode, Path]) ->
    Result = propose(mode(Mode), Path),
    io:put_chars(json:encode(hls_diagnostic:json_value(Result))),
    halt(0);
dispatch(["write", Plan, Bundle]) ->
    Result = write(Plan, Bundle),
    io:put_chars(json:encode(hls_diagnostic:json_value(Result))),
    halt(0);
dispatch(["revise", Plan, Implementation, Evidence, Metrics, Characterization, Revised]) ->
    Result = revise(
        Plan,
        unicode:characters_to_binary(Implementation),
        unicode:characters_to_binary(Evidence),
        Metrics,
        Characterization,
        Revised
    ),
    io:put_chars(json:encode(hls_diagnostic:json_value(Result))),
    halt(0);
dispatch(_Arguments) ->
    halt(2).

-doc "Writes one fresh local3 or shared3 implementation plan for the maintained arithmetic fixture.".
-spec propose(local3 | shared2 | shared3, file:filename()) -> map().
propose(Mode, Path) ->
    {Members, Sharing} = mode_policy(Mode),
    Config = configuration(Members),
    Program = hls_protocol_transport:prepare(Config),
    #{topology := Topology} = hls_protocol_transport:bundle(Program),
    Plan = hls_spacetime_plan:propose(Topology, [xc7], #{
        sharing => Sharing,
        constraints => feedback_constraints(),
        capabilities => #{source_protocol => #{scalar_completion => true}},
        planner => <<"stage5 arithmetic feedback">>,
        inputs => [atom_to_binary(Mode)]
    }),
    ok = write_term(Path, Plan),
    summary(Plan).

-doc "Writes a planned network source bundle from one retained plan; target projection rechecks the freshly prepared topology.".
-spec write(file:filename(), file:filename()) -> map().
write(PlanPath, BundlePath) ->
    Plan = read_plan(PlanPath),
    ok = witness_plan(Plan),
    Members = map_size(hls_implementation_plan:placement(Plan)),
    Build = hls_build:plan(#{
        backend => source_protocol,
        kind => network,
        configuration => configuration(Members),
        implementation_plan => Plan,
        target => xc7
    }),
    Manifest = hls_build:write(Build, BundlePath),
    (summary(Plan))#{provenance => maps:get(provenance, Manifest)}.

-doc "Binds matched routed metrics to the exact plan and realized implementation, applies the finite resource/timing policy and writes the characterization plus revised plan. local3 proposes sharing only after timing feasibility and replicated DSP use are observed; shared3 is retained only when it meets one-DSP and nonnegative-slack gates.".
-spec revise(
    file:filename(), binary(), binary(), file:filename(), file:filename(), file:filename()
) -> map().
revise(PlanPath, Implementation, Evidence, MetricsPath, CharacterizationPath, RevisedPath) ->
    true = sha256(Implementation),
    true = sha256(Evidence),
    Plan = read_plan(PlanPath),
    ok = witness_plan(Plan),
    Metrics = read_metrics(MetricsPath),
    Case = maps:get('case', Metrics),
    Scope = <<
        "One exact ",
        (atom_to_binary(Case))/binary,
        " planned arithmetic implementation; fixed part, clock and directives; single-threaded route recipe"
    >>,
    Characterization = hls_characterization:new(
        hls_implementation_plan:identity(Plan),
        Implementation,
        Evidence,
        native_measurement,
        Scope,
        Metrics
    ),
    {Action, Policy} = policy(Metrics),
    Revised =
        case Action of
            retain -> Plan;
            _ -> hls_spacetime_plan:revise(Plan, Implementation, Characterization, Policy)
        end,
    ok = write_term(CharacterizationPath, Characterization),
    ok = write_term(RevisedPath, Revised),
    (summary(Revised))#{
        action => Action,
        parent_plan => hls_implementation_plan:identity(Plan),
        characterization => hls_characterization:identity(Characterization),
        implementation => Implementation,
        evidence => Evidence
    }.

%% The public config contains no raw placement field; the implementation plan owns sharing.
-spec configuration(2..3) -> hls_source_config:network().
configuration(Members) ->
    #{
        sources => [{"apps/hls_fabric/test/hls_protocol_arithmetic_fixture.erl", []}],
        topology => {hls_protocol_arithmetic_fixture, topology, [Members]},
        actor_limit => 3
    }.

%% Parse only the two named finite candidates without allocating atoms from input.
-spec mode(string()) -> local3 | shared2 | shared3.
mode("local3") -> local3;
mode("shared2") -> shared2;
mode("shared3") -> shared3.

%% Select the actor population and explicit sharing policy named by the finite case.
-spec mode_policy(local3 | shared2 | shared3) -> {2..3, none | {by_module, 2..3}}.
mode_policy(local3) -> {3, none};
mode_policy(shared2) -> {2, {by_module, 2}};
mode_policy(shared3) -> {3, {by_module, 3}}.

%% Return a compact JSON-compatible report without serializing the executable plan value.
-spec summary(hls_implementation_plan:plan()) -> map().
summary(Plan) ->
    #{
        logical_system => hls_implementation_plan:logical_system(Plan),
        plan => hls_implementation_plan:identity(Plan),
        schedule_count => length(hls_implementation_plan:schedules(Plan)),
        provenance => hls_implementation_plan:provenance(Plan)
    }.

%% Select the deliberately finite local/shared policy from complete routed timing metrics.
-spec policy(map()) -> {share | retain | revert, fun((term(), term()) -> {map(), [map()]})}.
policy(Metrics = #{'case' := local3, resources := #{dsp := Dsp}}) ->
    case timing_feasible(Metrics) andalso Dsp > 1 of
        true ->
            {share, fun(Plan, _Characterization) ->
                {hls_implementation_plan:placement(Plan), [shared_schedule(Plan)]}
            end};
        false ->
            {retain, fun(Plan, _Characterization) ->
                {hls_implementation_plan:placement(Plan), hls_implementation_plan:schedules(Plan)}
            end}
    end;
policy(Metrics = #{'case' := shared3, resources := #{dsp := Dsp}}) ->
    case timing_feasible(Metrics) andalso Dsp =< 1 of
        true ->
            {retain, fun(Plan, _Characterization) ->
                {hls_implementation_plan:placement(Plan), hls_implementation_plan:schedules(Plan)}
            end};
        false ->
            {revert, fun(Plan, _Characterization) ->
                {hls_implementation_plan:placement(Plan), []}
            end}
    end.

%% Timing feasibility requires every reported setup, hold and pulse gate plus internal coverage.
-spec timing_feasible(map()) -> boolean().
timing_feasible(#{
    timing := #{
        worst_slack_ns := Setup,
        setup_failing_endpoints := 0,
        worst_hold_slack_ns := Hold,
        hold_failing_endpoints := 0,
        worst_pulse_slack_ns := Pulse,
        pulse_failing_endpoints := 0
    },
    coverage := #{no_clock := 0, unconstrained_internal_endpoints := 0}
}) ->
    Setup >= 0 andalso Hold >= 0 andalso Pulse >= 0;
%% Any missing, failing or noncanonical timing gate is infeasible.
timing_feasible(_) ->
    false.

%% The maintained fixture has one homogeneous module and exactly three actor identities.
-spec shared_schedule(hls_implementation_plan:plan()) -> hls_implementation_plan:schedule().
shared_schedule(Plan) ->
    Members = lists:sort(maps:keys(hls_implementation_plan:placement(Plan))),
    [Target] = lists:usort(maps:values(hls_implementation_plan:placement(Plan))),
    #{
        id => {schedule, Target, hls_protocol_arithmetic_fixture, 0},
        target => Target,
        module => hls_protocol_arithmetic_fixture,
        members => Members
    }.

%% Decode only the closed physical comparison schema used by the witness.
-spec read_metrics(file:filename()) -> map().
read_metrics(Path) ->
    {ok, Bytes} = file:read_file(Path),
    Decoded =
        #{
            <<"case">> := Case,
            <<"resources">> := #{<<"dsp">> := Dsp, <<"lut">> := Lut, <<"ff">> := Ff},
            <<"timing">> := #{
                <<"worst_slack_ns">> := Setup,
                <<"setup_failing_endpoints">> := SetupFailures,
                <<"worst_hold_slack_ns">> := Hold,
                <<"hold_failing_endpoints">> := HoldFailures,
                <<"worst_pulse_slack_ns">> := Pulse,
                <<"pulse_failing_endpoints">> := PulseFailures
            },
            <<"coverage">> := #{
                <<"no_clock">> := NoClock,
                <<"unconstrained_internal_endpoints">> := Unconstrained
            }
        } = json:decode(Bytes),
    4 = map_size(Decoded),
    3 = map_size(maps:get(<<"resources">>, Decoded)),
    6 = map_size(maps:get(<<"timing">>, Decoded)),
    2 = map_size(maps:get(<<"coverage">>, Decoded)),
    true = lists:member(Case, [<<"local3">>, <<"shared3">>]),
    true = is_integer(Dsp) andalso Dsp >= 0,
    true = is_integer(Lut) andalso Lut >= 0,
    true = is_integer(Ff) andalso Ff >= 0,
    true = lists:all(fun is_number/1, [Setup, Hold, Pulse]),
    true = lists:all(
        fun(Value) -> is_integer(Value) andalso Value >= 0 end,
        [SetupFailures, HoldFailures, PulseFailures, NoClock, Unconstrained]
    ),
    #{
        'case' => binary_to_existing_atom(Case),
        resources => #{dsp => Dsp, lut => Lut, ff => Ff},
        timing => #{
            worst_slack_ns => Setup,
            setup_failing_endpoints => SetupFailures,
            worst_hold_slack_ns => Hold,
            hold_failing_endpoints => HoldFailures,
            worst_pulse_slack_ns => Pulse,
            pulse_failing_endpoints => PulseFailures
        },
        coverage => #{no_clock => NoClock, unconstrained_internal_endpoints => Unconstrained}
    }.

%% The fixed Tcl recipe and finite policy support exactly this plan constraint vocabulary.
-spec feedback_constraints() -> map().
feedback_constraints() -> #{clock_period_ns => 10.0, objective => minimize_dsp}.

%% Correlate hardcoded route/policy settings with the plan before emission or characterization.
-spec witness_plan(hls_implementation_plan:plan()) -> ok.
witness_plan(Plan) ->
    Expected = feedback_constraints(),
    case hls_implementation_plan:constraints(Plan) of
        Expected -> ok;
        Other -> error({unsupported_feedback_constraints, Other})
    end.

%% Read one trusted local plan; validation rejects decoded live values before use.
-spec read_plan(file:filename()) -> hls_implementation_plan:plan().
read_plan(Path) ->
    {ok, Bytes} = file:read_file(Path),
    _ = hls_implementation_plan:validate(#{}),
    Plan = binary_to_term(Bytes, [safe]),
    ok = hls_implementation_plan:validate(Plan),
    Plan.

%% Persist deterministic trusted-local evidence once; callers allocate fresh paths.
-spec write_term(file:filename(), term()) -> ok.
write_term(Path, Term) ->
    ok = filelib:ensure_dir(Path),
    file:write_file(Path, term_to_binary(Term, [deterministic]), [exclusive]).

%% Physical correlation uses the same lowercase SHA-256 text shape as build receipts.
-spec sha256(term()) -> boolean().
sha256(Value) when is_binary(Value), byte_size(Value) =:= 64 ->
    lists:all(
        fun(Byte) ->
            (Byte >= $0 andalso Byte =< $9) orelse (Byte >= $a andalso Byte =< $f)
        end,
        binary_to_list(Value)
    );
sha256(_) ->
    false.

%% A retained decision describes the implementation just characterized, not an unrealized child.
-spec retain_keeps_realized_plan_test() -> ok.
retain_keeps_realized_plan_test() ->
    Root = filename:join(
        temporary_directory(),
        "hls-spacetime-feedback-" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))
    ),
    PlanPath = filename:join(Root, "plan.etf"),
    MetricsPath = filename:join(Root, "metrics.json"),
    CharacterizationPath = filename:join(Root, "characterization.etf"),
    RevisedPath = filename:join(Root, "revised.etf"),
    try
        Plan = retained_plan(),
        ok = write_term(PlanPath, Plan),
        Proposed = summary(Plan),
        ok = file:write_file(
            MetricsPath,
            json:encode(#{
                <<"case">> => <<"shared3">>,
                <<"resources">> => #{<<"dsp">> => 1, <<"lut">> => 1, <<"ff">> => 1},
                <<"timing">> => #{
                    <<"worst_slack_ns">> => 0.0,
                    <<"setup_failing_endpoints">> => 0,
                    <<"worst_hold_slack_ns">> => 0.0,
                    <<"hold_failing_endpoints">> => 0,
                    <<"worst_pulse_slack_ns">> => 0.0,
                    <<"pulse_failing_endpoints">> => 0
                },
                <<"coverage">> => #{
                    <<"no_clock">> => 0,
                    <<"unconstrained_internal_endpoints">> => 0
                }
            })
        ),
        Result = revise(
            PlanPath,
            list_to_binary(lists:duplicate(64, $a)),
            list_to_binary(lists:duplicate(64, $b)),
            MetricsPath,
            CharacterizationPath,
            RevisedPath
        ),
        ?assertEqual(retain, maps:get(action, Result)),
        ?assertEqual(maps:get(plan, Proposed), maps:get(plan, Result)),
        {ok, Bytes} = file:read_file(CharacterizationPath),
        Characterization = binary_to_term(Bytes, [safe]),
        ?assertMatch(
            <<"One exact shared3 planned arithmetic implementation;", _/binary>>,
            hls_characterization:scope(Characterization)
        )
    after
        ok = file:del_dir_r(Root)
    end.

%% Build the retain-policy witness without importing another application's test fixture.
-spec retained_plan() -> hls_implementation_plan:plan().
retained_plan() ->
    Members = [{actor, arithmetic_a}, {actor, arithmetic_b}, {actor, arithmetic_c}],
    Target = xc7,
    hls_implementation_plan:new(
        <<"retained-arithmetic-system">>,
        maps:from_list([{Member, Target} || Member <- Members]),
        [
            #{
                id => retained_arithmetic_schedule,
                target => Target,
                module => hls_spacetime_feedback_fixture,
                members => Members
            }
        ],
        feedback_constraints(),
        #{source_protocol => #{scalar_completion => true}},
        #{planner => <<"stage5 arithmetic feedback fixture">>, inputs => [<<"shared3">>]}
    ).

%% A failed timing or coverage gate cannot select the resource-saving shared implementation.
-spec failed_timing_is_not_selected_test() -> ok.
failed_timing_is_not_selected_test() ->
    Metrics = #{
        'case' => local3,
        resources => #{dsp => 3, lut => 1, ff => 1},
        timing => #{
            worst_slack_ns => 1.0,
            setup_failing_endpoints => 0,
            worst_hold_slack_ns => -0.1,
            hold_failing_endpoints => 1,
            worst_pulse_slack_ns => 1.0,
            pulse_failing_endpoints => 0
        },
        coverage => #{no_clock => 0, unconstrained_internal_endpoints => 0}
    },
    {retain, _} = policy(Metrics),
    {retain, _} = policy(Metrics#{
        timing := (maps:get(timing, Metrics))#{
            worst_hold_slack_ns := 1.0, hold_failing_endpoints := 0
        },
        coverage := #{no_clock => 0, unconstrained_internal_endpoints => 1}
    }),
    ok.

%% A plan clock/objective drift is rejected before source or evidence is accepted.
-spec constraint_drift_is_rejected_test() -> ok.
constraint_drift_is_rejected_test() ->
    Base = retained_plan(),
    Drifted = hls_implementation_plan:new(
        hls_implementation_plan:logical_system(Base),
        hls_implementation_plan:placement(Base),
        hls_implementation_plan:schedules(Base),
        #{clock_period_ns => 5.0, objective => minimize_dsp},
        hls_implementation_plan:capabilities(Base),
        hls_implementation_plan:provenance(Base)
    ),
    ?assertError(
        {unsupported_feedback_constraints, #{clock_period_ns := 5.0}},
        witness_plan(Drifted)
    ).

%% Locate an existing writable temporary root for isolated fixture evidence.
-spec temporary_directory() -> file:filename().
temporary_directory() ->
    case os:getenv("TMPDIR") of
        false -> "/tmp";
        Value -> Value
    end.
