-module(hls_protocol_ingress_tests).
-include_lib("eunit/include/eunit.hrl").

%% Full-width payloads stay unconstrained; malformed header and padding do not.
-spec schema_domain_test() -> ok.
schema_domain_test() ->
    Artifact = artifact([work], u32),
    [#{mask := Mask, value := Value}] = hls_protocol_schema:domains(Artifact, [work]),
    [Frame] = hls_protocol_schema:frames(Artifact, [{work, 16#ffffffff}]),
    ?assertEqual(Value, Frame band Mask),
    ?assertNotEqual(Value, (Frame bor (1 bsl 64)) band Mask),
    ?assertNotEqual(Value, (Frame bxor (1 bsl 8)) band Mask),
    ?assertError({invalid_ingress_schemas, []}, hls_protocol_schema:domains(Artifact, [])),
    ?assertError({invalid_ingress_schemas, [work, work]},
        hls_protocol_schema:domains(Artifact, [work, work])),
    ?assertError({undeclared_protocol_schema, other},
        hls_protocol_schema:domains(Artifact, [other])).

%% One shared command covers all selected actor identities without duplicating frames.
-spec binding_test() -> ok.
binding_test() ->
    Bundle = bundle(), Plan = hls_protocol_ingress:plan(Bundle),
    ?assertEqual(131, maps:get(state_bits, Plan)),
    ?assert(hls_protocol_ingress:addressed(Plan, 0)),
    ?assert(hls_protocol_ingress:addressed(Plan, 1)),
    ?assertNot(hls_protocol_ingress:addressed(Plan, 2)),
    ?assertNot(hls_protocol_ingress:addressed(none, 0)),
    #{topology := Topology} = Bundle,
    ?assertEqual(none, hls_protocol_ingress:plan(Bundle#{topology := Topology#{ingresses := []}})).

%% Valid destination schemas must agree on operation numbers and exact scalar types.
-spec mismatched_codec_test() -> ok.
mismatched_codec_test() ->
    Bundle = #{modules := #{a := Unsigned}} = bundle(),
    ?assertError({incompatible_ingress_schemas, all}, hls_protocol_ingress:plan(
        Bundle#{modules := #{a => Unsigned, b => artifact([other, work], u32)}})),
    ?assertError({incompatible_ingress_schemas, all}, hls_protocol_ingress:plan(
        Bundle#{modules := #{a => Unsigned, b => artifact([work], s32)}})).

%% Missing schemas, duplicate recipients and unsupported boundaries fail before generation.
-spec rejects_ambiguous_test() -> ok.
rejects_ambiguous_test() ->
    Bundle = #{topology := Topology = #{ingresses := [Ingress = #{targets :=
        [Target = #{recipients := [First | _]}]}]}} = bundle(),
    Check = fun(New) ->
        hls_protocol_ingress:plan(Bundle#{topology := Topology#{ingresses := [New]}})
    end,
    ?assertError({ambiguous_ingress_recipients, all},
        Check(Ingress#{targets := [Target#{recipients := [First, First]}]})),
    Missing = maps:remove(schemas, Target),
    ?assertError({invalid_ingress_target, Missing}, Check(Ingress#{targets := [Missing]})),
    ?assertException(error, _, Check(Ingress#{shape := [65537, 1]})),
    ?assertException(error, _, hls_protocol_ingress:plan(
        Bundle#{topology := Topology#{ingresses := [Ingress, Ingress]}})).

%% Both actor instances share the same freshly compiled module and explicit source binding.
-spec bundle() -> map().
bundle() ->
    Artifact = artifact([work], u32),
    #{topology => #{actors => [#{id => left, module => a}, #{id => right, module => b}],
        ingresses => [#{id => host, kind => rectangle, shape => [3, 2], targets => [
            #{id => all, schemas => [work], recipients => [
                #{actor => left, at => [0, 0]}, #{actor => right, at => [2, 1]}]}]}]},
        modules => #{a => Artifact, b => Artifact}}.

%% Tag order and scalar type come from complete source declarations, not fabricated ASTs.
-spec artifact([atom(), ...], atom()) -> hls_local_actor:artifact().
artifact(Names, Type) ->
    Fields = [{n, "hls_nums:" ++ atom_to_list(Type) ++ "()"}],
    hls_protocol_schema_test_source:compile([{Name, Fields} || Name <- Names]).
