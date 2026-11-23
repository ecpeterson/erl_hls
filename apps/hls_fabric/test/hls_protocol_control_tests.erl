-module(hls_protocol_control_tests).
-moduledoc "Source control schemas, target coordinates and native projections share one checked plan; finite host checks do not qualify hardware or application progress.".
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
    ?assertError({hls_diagnostic, #{stage := schema, code := invalid_ingress_schemas, context := #{schemas := []}}}, hls_protocol_schema:domains(Artifact, [])),
    ?assertError({hls_diagnostic, #{code := invalid_ingress_schemas, context := #{schemas := [work, work]}}},
        hls_protocol_schema:domains(Artifact, [work, work])),
    ?assertError({hls_diagnostic, #{code := undeclared_protocol_schema, context := #{schema := other}}},
        hls_protocol_schema:domains(Artifact, [other])).

%% Compact finite atoms retain their exact codec width without pretending to be integers.
-spec finite_atom_domain_test() -> ok.
finite_atom_domain_test() ->
    Artifact = hls_protocol_schema_test_source:compile(
        [{status, [{value, "ready | busy | failed"}]}]),
    [#{mask := Mask, value := Value}] = hls_protocol_schema:domains(Artifact, [status]),
    [Ready, Busy, Failed] = hls_protocol_schema:frames(Artifact,
        [{status, ready}, {status, busy}, {status, failed}]),
    ?assertEqual(3, length(lists:usort([Ready, Busy, Failed]))),
    ?assertEqual([Value, Value, Value], [Frame band Mask || Frame <- [Ready, Busy, Failed]]).

%% Declared calls preserve their bounded wire slot; ordinary casts still require transaction zero.
-spec call_transaction_domain_test() -> ok.
call_transaction_domain_test() ->
    Source = hls_local_actor:prepare("apps/hls_fabric/test/hls_protocol_call_fixture.erl", []),
    [#{mask := Mask, value := Value}] = hls_protocol_schema:domains(Source, [read]),
    Frame = Value,
    ?assertError({hls_diagnostic, #{code := unsupported_startup_call, context := #{schema := read}}},
        hls_protocol_schema:frames(Source, [{read, 0}])),
    Transaction = 16#ff bsl hls_frame_layout:header_offset(txid),
    ?assertEqual(0, Mask band Transaction),
    ?assertEqual(Value, (Frame bor Transaction) band Mask),
    [#{mask := CastMask}] = hls_protocol_schema:domains(artifact([work], u8), [work]),
    ?assertEqual(Transaction, CastMask band Transaction).

%% One shared command covers all selected actor identities without duplicating frames.
-spec binding_test() -> ok.
binding_test() ->
    Bundle = bundle(), Plan = hls_protocol_control:plan(Bundle),
    ?assertEqual(131, maps:get(state_bits, Plan)),
    ?assert(hls_protocol_control:addressed(Plan, 0)),
    ?assert(hls_protocol_control:addressed(Plan, 1)),
    ?assertNot(hls_protocol_control:addressed(Plan, 2)),
    ?assertNot(hls_protocol_control:addressed(none, 0)),
    #{topology := Topology} = Bundle,
    ?assertEqual(none, hls_protocol_control:plan(Bundle#{topology := Topology#{ingresses := []}})).

%% Valid destination schemas must agree on operation numbers and exact scalar types.
-spec mismatched_codec_test() -> ok.
mismatched_codec_test() ->
    Bundle = #{modules := #{a := Unsigned}} = bundle(),
    ?assertError({hls_diagnostic, #{stage := control, code := incompatible_ingress_schemas,
        context := #{ingress := host, target := all}}}, hls_protocol_control:plan(
        Bundle#{modules := #{a => Unsigned, b => artifact([other, work], u32)}})),
    ?assertError({hls_diagnostic, #{stage := control, code := incompatible_ingress_schemas,
        context := #{ingress := host, target := all}}}, hls_protocol_control:plan(
        Bundle#{modules := #{a => Unsigned, b => artifact([work], s32)}})).

%% Missing schemas, duplicate recipients and unsupported boundaries fail before generation.
-spec rejects_ambiguous_test() -> ok.
rejects_ambiguous_test() ->
    Bundle = #{topology := Topology = #{ingresses := [Ingress = #{targets :=
        [Target = #{recipients := [First | _]}]}]}} = bundle(),
    Check = fun(New) ->
        hls_protocol_control:plan(Bundle#{topology := Topology#{ingresses := [New]}})
    end,
    ?assertError({hls_diagnostic, #{code := ambiguous_ingress_recipients, context := #{target := all}}},
        Check(Ingress#{targets := [Target#{recipients := [First, First]}]})),
    Missing = maps:remove(schemas, Target),
    ?assertError({hls_diagnostic, #{code := invalid_ingress_target, context := #{value := Missing}}},
        Check(Ingress#{targets := [Missing]})),
    ?assertError({hls_diagnostic, #{stage := control, code := unsupported_protocol_ingress}},
        Check(Ingress#{shape := [65537, 1]})),
    ?assertError({hls_diagnostic, #{stage := control, code := unsupported_protocol_ingress}},
        hls_protocol_control:plan(Bundle#{topology := Topology#{ingresses := [Ingress, Ingress]}})).

%% A shared actor keeps each target's coordinates; native projection cannot replace the host plan.
-spec target_coordinates_and_projection_test() -> ok.
target_coordinates_and_projection_test() ->
    Module = hls_protocol_boundary_fixture,
    Artifact = hls_local_actor:compile("apps/hls_fabric/test/hls_protocol_boundary_fixture.erl", []),
    Actors = [#{id => Id, module => Module} || Id <- [left, right]],
    Targets = [#{id => near, schemas => [work], recipients => [
        #{actor => left, at => [0, 0]}, #{actor => right, at => [1, 0]}]},
        #{id => far, schemas => [work], recipients => [#{actor => left, at => [3, 0]}]}],
    Whole = hls_protocol_control:plan(#{frame_layout => hls_frame_layout:default(), modules => #{Module => Artifact},
        topology => #{actors => Actors, ingresses => [#{id => host, kind => rectangle,
            shape => [4, 1], targets => Targets}]}}),
    Native = hls_protocol_control:project(Whole, [1]),
    ?assertMatch(#{actors := 2, targets := [#{recipients := [#{index := 1}]},
        #{recipients := []}]}, Native),
    ?assertNot(hls_protocol_control:addressed(Native, 0)),
    ?assert(hls_protocol_control:addressed(Whole, 0)),
    ?assertEqual(none, hls_protocol_control:project(none, [1])),
    Codecs = hls_host_codec_plan:schemas(hls_actor_interface:from_module(Module)),
    Bound = [A#{index => I, device => maps:get(id, A), schemas => Codecs}
        || {I, A} <- lists:enumerate(0, Actors)],
    Partition = #{ingresses => hls_protocol_control:host_ingresses(Whole, Bound)},
    Application = #{partition => Partition, devices => #{
        left => #{host => 2, control => 7, ingress => host},
        right => #{host => 3, control => 7, ingress => host}}},
    Command = {host, far, {3, 0, 3, 0}, {work, 42}},
    {Bytes, [0], {work, 42}} = hls_protocol_application_codec:delivery(Application, Command),
    Tag = Module:pack_tag(work),
    ?assertEqual(<<3:16/little, 0:16/little, 3:16/little, 0:16/little,
        1:32/little, 1:8, 0:16, Tag:8, 42:32/little>>, Bytes),
    ?assertEqual([{left, {2, 7}, {2, 0, 0}, Bytes}], hls_partition_wire:command(Application, Command)),
    ?assertEqual({Bytes, [0], {work, 42}}, hls_protocol_mixed_host:controls(
        #{application => Application, actors => #{0 => #{}}}, Command)),
    ?assertEqual([], hls_partition_ingress:commands(Partition, host, far, {0, 0, 0, 0}, {work, 42})),
    ?assertException(error, _, hls_protocol_application_codec:delivery(Application,
        {host, far, {0, 0, 0, 0}, {work, 42}})),
    {_, [0, 1], {work, 42}} = hls_protocol_application_codec:delivery(Application,
        {host, near, {0, 0, 1, 0}, {work, 42}}),
    ?assertEqual([], hls_protocol_control:host_ingresses(none, Bound)).

%% Framing accepts only the implemented adapter/activation and its exact sampled handshake.
-spec framed_capabilities_test() -> ok.
framed_capabilities_test() ->
    Control = #{kind => rectangle, input_bits => 194},
    Hardware = hls_protocol_control:framed(Control, #{}),
    ?assertMatch(#{input_bits := 194, command_bits := 195}, Hardware),
    ?assertError({hls_diagnostic, #{stage := control, code := unsupported_framed_control, context := #{control := none}}},
        hls_protocol_control:framed(none, #{})),
    ?assertError({hls_diagnostic, #{code := unsupported_framed_control, context := #{control := other, activation := explicit_start}}},
        hls_protocol_control:framed(Control, #{control => other})),
    ?assertError({hls_diagnostic, #{code := unsupported_framed_control, context := #{control := rectangle, activation := automatic}}},
        hls_protocol_control:framed(Control, #{activation => automatic})),
    ?assertEqual({[], []}, hls_protocol_control:ports(none)),
    {Inputs, Outputs} = hls_protocol_control:ports(Control),
    ?assert(lists:member({"ingress_data", 194}, Inputs)),
    Boundary = #{activation => explicit_start,
        inputs => [#{name => list_to_binary(Name), width => Width}
            || {Name, Width} <- Inputs ++ [{"start_valid", 1}]],
        outputs => [#{name => list_to_binary(Name), width => Width}
            || {Name, Width} <- Outputs ++ [{"start_ready", 1}]]},
    ?assertEqual(ok, hls_protocol_control:check_boundary(Hardware, Boundary)),
    Bad = Boundary#{inputs := [case P of
        #{name := <<"ingress_data">>} -> P#{width := 193};
        _ -> P
    end || P <- maps:get(inputs, Boundary)]},
    ?assertError(control_boundary_mismatch, hls_protocol_control:check_boundary(Hardware, Bad)).

%% Both actor instances share the same freshly compiled module and explicit source binding.
-spec bundle() -> map().
bundle() ->
    Artifact = artifact([work], u32),
    #{frame_layout => hls_frame_layout:default(), topology => #{actors => [#{id => left, module => a}, #{id => right, module => b}],
        ingresses => [#{id => host, kind => rectangle, shape => [3, 2], targets => [
            #{id => all, schemas => [work], recipients => [
                #{actor => left, at => [0, 0]}, #{actor => right, at => [2, 1]}]}]}]},
        modules => #{a => Artifact, b => Artifact}}.

%% Tag order and scalar type come from complete source declarations, not fabricated ASTs.
-spec artifact([atom(), ...], atom()) -> hls_local_actor:artifact().
artifact(Names, Type) ->
    Fields = [{n, "hls_nums:" ++ atom_to_list(Type) ++ "()"}],
    hls_protocol_schema_test_source:compile([{Name, Fields} || Name <- Names]).

%% Native capacity changes handshake/storage widths; fixed framing rejects excess capacity before rendering.
-spec selected_frame_capacity_test() -> ok.
selected_frame_capacity_test() ->
    Layout = hls_frame_layout:new(1),
    Artifact = hls_local_actor:prepare("apps/hls_fabric/test/hls_protocol_frame_fixture.erl", [], Layout),
    Plan = hls_protocol_control:plan(#{frame_layout => Layout,
        modules => #{hls_protocol_frame_fixture => Artifact},
        topology => #{actors => [#{id => cell, module => hls_protocol_frame_fixture}],
            ingresses => [#{id => host, kind => rectangle, shape => [1, 1],
                targets => [#{id => all, schemas => [small], recipients => [#{actor => cell, at => [0, 0]}]}]}]}}),
    ?assertMatch(#{input_bits := 130, state_bits := 66}, Plan),
    ?assertMatch(#{input_bits := 130, command_bits := 131, frame_layout := Layout},
        hls_protocol_control:framed(Plan, #{})),
    ?assertError({hls_diagnostic, #{code := framed_payload_capacity,
        context := #{payload_bits := 128, maximum := 96}}},
        hls_protocol_control:framed(Plan#{frame_layout := hls_frame_layout:new(4), input_bits := 226}, #{})).
