-module(hls_observation_build).
-moduledoc """
Canonical correlation identity for one observed implementation build. The four opaque components
bind source input, generated RTL, observation interpretation and realized implementation without
asserting that any component is a digest, path or human-readable string. This module checks shape and
agreement only; callers own the evidence that assigns each identity.
""".

-export([new/4, validate/1, validate_component/1, match/2]).
-export_type([build/0, component/0, validation_error/0, match_error/0]).

-doc "One required correlation component in the stable build map.".
-type component() :: source | rtl | observation | implementation.

-doc "Exact correlation map shared by execution, physical and observation artifacts.".
-type build() :: #{
    source := binary(),
    rtl := binary(),
    observation := binary(),
    implementation := binary()
}.

-doc "Shape or opaque-component failure. Components are valid when they are nonempty binaries.".
-type validation_error() :: invalid_shape | {invalid_component, component(), term()}.

-doc "Exact-build disagreement, including which required component differed when available.".
-type match_error() ::
    {invalid_expected, validation_error()}
    | {invalid_actual, validation_error()}
    | {component_mismatch, component(), binary(), error | {ok, term()}}.

-doc "Constructs the exact four-component map after validating every opaque identity. Raises {observation_build, Reason} for an empty or nonbinary component.".
-spec new(term(), term(), term(), term()) -> build().
new(Source, Rtl, Observation, Implementation) ->
    Build = #{
        source => Source,
        rtl => Rtl,
        observation => Observation,
        implementation => Implementation
    },
    case validate(Build) of
        ok -> Build;
        {error, Reason} -> error({observation_build, Reason})
    end.

-doc "Checks that a term is exactly the four-key build map and that every component is a nonempty binary. Binary contents remain opaque and need not be UTF-8 or a digest.".
-spec validate(term()) -> ok | {error, validation_error()}.
validate(
    #{
        source := Source,
        rtl := Rtl,
        observation := Observation,
        implementation := Implementation
    } = Build
) when
    map_size(Build) =:= 4
->
    validate_named([
        {source, Source},
        {rtl, Rtl},
        {observation, Observation},
        {implementation, Implementation}
    ]);
validate(_) ->
    {error, invalid_shape}.

-doc "Checks one opaque component independently of its role. Accepts every nonempty binary, including nontextual fixture identities.".
-spec validate_component(term()) -> ok | {error, invalid_component}.
validate_component(Value) when is_binary(Value), byte_size(Value) > 0 ->
    ok;
validate_component(_) ->
    {error, invalid_component}.

-doc "Checks exact agreement of two valid four-component maps. Reports the first RTL, source, implementation or observation difference, preserving the observer binding diagnostic order; rejects malformed maps even when their shared fields agree.".
-spec match(term(), term()) -> ok | {error, match_error()}.
match(Expected, Actual) ->
    case validate(Expected) of
        {error, Reason} ->
            {error, {invalid_expected, Reason}};
        ok ->
            case first_mismatch(Expected, Actual) of
                none ->
                    case validate(Actual) of
                        ok -> ok;
                        {error, Reason} -> {error, {invalid_actual, Reason}}
                    end;
                Mismatch ->
                    {error, Mismatch}
            end
    end.

%% Name component failures without imposing text or digest semantics.
-spec validate_named([{component(), term()}]) -> ok | {error, validation_error()}.
validate_named([]) ->
    ok;
validate_named([{Name, Value} | Rest]) ->
    case validate_component(Value) of
        ok -> validate_named(Rest);
        {error, invalid_component} -> {error, {invalid_component, Name, Value}}
    end.

%% Compare canonical components before reporting a less specific malformed actual map.
-spec first_mismatch(build(), term()) -> none | match_error().
first_mismatch(_Expected, Actual) when not is_map(Actual) ->
    none;
first_mismatch(Expected, Actual) ->
    first_mismatch([rtl, source, implementation, observation], Expected, Actual).

%% Component order makes mismatch diagnostics deterministic.
-spec first_mismatch([component()], build(), map()) -> none | match_error().
first_mismatch([], _Expected, _Actual) ->
    none;
first_mismatch([Name | Rest], Expected, Actual) ->
    ExpectedValue = maps:get(Name, Expected),
    case maps:find(Name, Actual) of
        {ok, ExpectedValue} -> first_mismatch(Rest, Expected, Actual);
        ActualValue -> {component_mismatch, Name, ExpectedValue, ActualValue}
    end.
