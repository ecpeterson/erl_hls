-module(hls_characterization).
-moduledoc """
Canonical supplied characterization for a realized implementation.

The contract binds metrics to one proposed-plan identity and one realized implementation. Method,
scope and evidence remain explicit so estimated, simulated, synthetic and native results cannot be
silently pooled. Validation establishes shape and correlation only, not evidence authenticity.
""".

-export([
    new/6,
    validate/1,
    identity/1,
    matches/2,
    matches/3,
    metrics/1,
    plan_identity/1,
    implementation_identity/1,
    evidence_identity/1,
    method/1,
    scope/1
]).
-export_type([characterization/0, method/0]).

-doc "Declared origin of the supplied measurements or estimates.".
-type method() :: analytical_model | simulation | synthetic_fixture | native_measurement.

-doc "One characterization bound to a proposed plan and realized implementation.".
-type characterization() :: #{
    version := 1,
    plan := binary(),
    implementation := binary(),
    evidence := binary(),
    method := method(),
    scope := binary(),
    metrics := map()
}.

-doc "Constructs a checked characterization. Invalid fields raise `{characterization, Reason}`.".
-spec new(binary(), binary(), binary(), method(), binary(), map()) -> characterization().
new(Plan, Implementation, Evidence, Method, Scope, Metrics) ->
    Characterization = #{
        version => 1,
        plan => Plan,
        implementation => Implementation,
        evidence => Evidence,
        method => Method,
        scope => Scope,
        metrics => Metrics
    },
    case validate(Characterization) of
        ok -> Characterization;
        {error, Reason} -> error({characterization, Reason})
    end.

-doc "Checks exact shape, nonempty correlation identities, declared method and a process-free metric map.".
-spec validate(term()) -> ok | {error, term()}.
validate(
    #{
        version := 1,
        plan := Plan,
        implementation := Implementation,
        evidence := Evidence,
        method := Method,
        scope := Scope,
        metrics := Metrics
    } = Characterization
) when map_size(Characterization) =:= 7 ->
    with([
        component(plan, Plan),
        component(implementation, Implementation),
        component(evidence, Evidence),
        validate_method(Method),
        component(scope, Scope),
        metrics_field(Metrics)
    ]);
validate(_) ->
    {error, invalid_shape}.

-doc "Returns a deterministic lowercase SHA-256 identity for one valid characterization.".
-spec identity(characterization()) -> binary().
identity(Characterization) ->
    ok = valid(Characterization),
    string:lowercase(
        binary:encode_hex(
            crypto:hash(sha256, term_to_binary(Characterization, [deterministic]))
        )
    ).

-doc "Checks only that a valid characterization names the exact identity of a valid proposed plan. Use `matches/3` when a realized implementation must also match.".
-spec matches(hls_implementation_plan:plan(), characterization()) -> ok | {error, term()}.
matches(Plan, Characterization) ->
    case {hls_implementation_plan:validate(Plan), validate(Characterization)} of
        {ok, ok} ->
            Expected = hls_implementation_plan:identity(Plan),
            case maps:get(plan, Characterization) of
                Expected -> ok;
                Actual -> {error, {plan_mismatch, Expected, Actual}}
            end;
        {{error, Why}, _} ->
            {error, {invalid_plan, Why}};
        {_, {error, Why}} ->
            {error, {invalid_characterization, Why}}
    end.

-doc "Checks that a valid characterization names both the valid proposed plan and the supplied nonempty realized-implementation identity.".
-spec matches(hls_implementation_plan:plan(), binary(), characterization()) ->
    ok | {error, term()}.
matches(Plan, Implementation, Characterization) ->
    case matches(Plan, Characterization) of
        ok ->
            case component(implementation, Implementation) of
                ok ->
                    case maps:get(implementation, Characterization) of
                        Implementation -> ok;
                        Actual -> {error, {implementation_mismatch, Implementation, Actual}}
                    end;
                {error, Why} ->
                    {error, Why}
            end;
        {error, _} = Error ->
            Error
    end.

-doc "Returns owner-defined metrics after validation.".
-spec metrics(characterization()) -> map().
metrics(Characterization) ->
    ok = valid(Characterization),
    maps:get(metrics, Characterization).

-doc "Returns the exact proposed-plan identity after validation.".
-spec plan_identity(characterization()) -> binary().
plan_identity(Characterization) ->
    ok = valid(Characterization),
    maps:get(plan, Characterization).

-doc "Returns the exact realized-implementation identity after validation.".
-spec implementation_identity(characterization()) -> binary().
implementation_identity(Characterization) ->
    ok = valid(Characterization),
    maps:get(implementation, Characterization).

-doc "Returns the opaque evidence identity after validation.".
-spec evidence_identity(characterization()) -> binary().
evidence_identity(Characterization) ->
    ok = valid(Characterization),
    maps:get(evidence, Characterization).

-doc "Returns the declared characterization method after validation.".
-spec method(characterization()) -> method().
method(Characterization) ->
    ok = valid(Characterization),
    maps:get(method, Characterization).

-doc "Returns the stated evidence scope after validation.".
-spec scope(characterization()) -> binary().
scope(Characterization) ->
    ok = valid(Characterization),
    maps:get(scope, Characterization).

%% Correlation fields are opaque nonempty binaries.
-spec component(atom(), term()) -> ok | {error, term()}.
component(_Name, Value) when is_binary(Value), byte_size(Value) > 0 -> ok;
component(Name, Value) -> {error, {invalid_component, Name, Value}}.

%% Only declared evidence classes may be compared by policy.
-spec validate_method(term()) -> ok | {error, term()}.
validate_method(Method) when
    Method =:= analytical_model;
    Method =:= simulation;
    Method =:= synthetic_fixture;
    Method =:= native_measurement
->
    ok;
validate_method(Method) ->
    {error, {invalid_method, Method}}.

%% Metric interpretation remains with the consumer, but live VM state cannot enter its identity.
-spec metrics_field(term()) -> ok | {error, term()}.
metrics_field(Metrics) when is_map(Metrics) ->
    case hls_static_term:validate(Metrics) of
        ok -> ok;
        {error, Kind} -> {error, {live_metrics_value, Kind}}
    end;
metrics_field(Metrics) ->
    {error, {invalid_metrics, Metrics}}.

%% Return the first invalid field in contract order.
-spec with([ok | {error, term()}]) -> ok | {error, term()}.
with([]) -> ok;
with([ok | Rest]) -> with(Rest);
with([{error, _} = Error | _]) -> Error.

%% Internal accessors preserve the public failure reason.
-spec valid(term()) -> ok.
valid(Characterization) ->
    case validate(Characterization) of
        ok -> ok;
        {error, Reason} -> error({characterization, Reason})
    end.
