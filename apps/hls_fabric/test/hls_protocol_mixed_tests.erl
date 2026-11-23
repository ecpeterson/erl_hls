-module(hls_protocol_mixed_tests).
-include_lib("eunit/include/eunit.hrl").
-export([topology/0, host_binding/0]).

%% The production mixed builder must retain host recipients removed from its native projection.
-spec whole_control_test() -> ok.
whole_control_test() ->
    Config = #{sources => [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []},
        {"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}, {?FILE, []}],
        topology => {?MODULE, topology, []}, actor_limit => 3,
        native_actors => [left, sink], host => 2, service => 29, control => rectangle},
    #{result := Plan = #{actors := Actors}} = hls_protocol_mixed:emit(Config),
    ?assertEqual([1], maps:keys(Actors)),
    ?assertMatch({_, [1], {total, 12}}, hls_protocol_mixed_host:controls(
        Plan, {host, all, {1, 0, 1, 0}, {total, 12}})),
    ?assertMatch({_, [], {total, 12}}, hls_protocol_mixed_host:controls(
        Plan, {host, all, {0, 0, 0, 0}, {total, 12}})).

-doc "Keeps the feedback fixture's native multicast but gives each BEAM output one destination, as required by mixed placement.".
-spec topology() -> map().
topology() ->
    T = #{routes := Routes} = hls_protocol_network_fixture:framed(),
    T#{routes := [case R of
        {From = {right, _}, buffered, [First | _]} -> {From, [First]};
        _ -> R
    end || R <- Routes]}.

%% Host placement preserves startup order and duplicates while separating native and external targets.
-spec host_binding_test() -> ok.
host_binding_test() ->
    Config = #{sources => [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []},
        {"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}, {?FILE, []}],
        topology => {?MODULE, host_binding, []}, actor_limit => 3,
        native_actors => [left, sink], host => 2, service => 29, control => rectangle},
    #{actors := #{1 := HostActor}, targets := Targets, application := Application} =
        hls_protocol_mixed:descriptor(hls_protocol_mixed:plan(Config)),
    ?assertMatch(#{id := right, module := hls_protocol_network_fixture, capacity := 8,
        outputs := #{early := {actor, sink}, open := {actor, sink}, later := {external, right}},
        startup := [{total, 3}, {total, 1}, {total, 3}],
        schemas := #{value := #{codec := _}, go := #{codec := _}, total := #{codec := _}},
        output_schemas := #{early := [value], open := [go], later := [value]}}, HostActor),
    ?assertEqual(#{{actor, left} => {actor, 0}, {actor, sink} => {actor, 2},
        {external, right} => {external, right}}, Targets),
    #{partition := #{actors := BoundActors}} = Application,
    ?assertEqual([{left, 0, board}, {right, 1, board}, {sink, 2, board}],
        [{Id, Index, Device} || #{id := Id, index := Index, device := Device} <- BoundActors]).

-doc "Adds ordered host startup records and one external-only output to the mixed fixture's otherwise native feedback routes.".
-spec host_binding() -> map().
host_binding() ->
    Topology = #{routes := Routes} = topology(),
    Topology#{startup := [{right, [{total, 3}, {total, 1}, {total, 3}]}],
        routes := [case Route of
            {{right, later}, _} -> {{right, later}, [{external, right}]};
            _ -> Route
        end || Route <- Routes]}.

%% Crossing operation numbering belongs to the destination; use a deliberately different selector.
-spec destination_selector_test() -> ok.
destination_selector_test() ->
    M=hls_protocol_network_fixture,Op=17,?assertNotEqual(Op,M:pack_tag(value)),
    C=hls_protocol_codec_plan:plan(#{message_bits=>32,payload_bits=>32,
        fields=>[#{type=>{hls_type,hls_nums,uN,[32]},message_bit_offset=>0,capture_bit_offset=>0}]},Op),
    Record=hls_record_codec:bind(value,[{value,hls_nums:u32()}]),
    L=#{source_module=>M,destination_module=>M,
        classes=>[#{slot=>2,port=>early,tag=>value,codec=>C,message_bits=>32,
            source_record=>Record,destination_record=>Record}]},
    {2,Frame}=hls_protocol_mixed_codec:encode(L,early,{value,16#12345678}),
    ?assertEqual(Op,(Frame bsr 24) band 255),
    ?assertEqual({value,16#12345678},hls_protocol_mixed_codec:decode(L,2,Frame)),
    ?assertError({badmatch,{error,invalid_frame}},hls_protocol_mixed_codec:decode(L,2,Frame bxor (1 bsl 8))).

%% A constant-only source class cannot transmit a different value even when its payload width is zero.
-spec omitted_constant_test() -> ok.
omitted_constant_test() ->
    M=hls_protocol_network_fixture,
    C=hls_protocol_codec_plan:plan(#{message_bits=>8,payload_bits=>0,
        fields=>[#{type=>{hls_type,hls_nums,uN,[8]},message_bit_offset=>0,constant=><<7>>}]},M:pack_tag(go)),
    Record=hls_record_codec:bind(go,[{key,hls_nums:u8()}]),
    L=#{source_module=>M,destination_module=>M,
        classes=>[#{slot=>0,port=>open,tag=>go,codec=>C,message_bits=>8,
            source_record=>Record,destination_record=>Record}]},
    {0,Frame}=hls_protocol_mixed_codec:encode(L,open,{go,7}),
    ?assertEqual({go,7},hls_protocol_mixed_codec:decode(L,0,Frame)),
    ?assertError({badmatch,{error,invalid_frame}},hls_protocol_mixed_codec:encode(L,open,{go,8})).

%% A retained mixed descriptor carries its record schema through an actor-module reload.
-spec retained_actor_codecs_test() -> ok.
retained_actor_codecs_test() ->
    Config = #{sources => [{"apps/hls_fabric/test/hls_protocol_network_fixture.erl", []},
        {"apps/hls_fabric/test/hls_protocol_inbox_fixture.erl", []}, {?FILE, []}],
        topology => {?MODULE, host_binding, []}, actor_limit => 3,
        native_actors => [left, sink], host => 2, service => 29, control => rectangle},
    Plan = hls_protocol_mixed:descriptor(hls_protocol_mixed:plan(Config)),
    #{mixed := #{links := Links}} = Plan,
    [Link] = [L || L = #{source_index := 1, destination_index := 2} <- Links],
    {Slot, Frame} = hls_protocol_mixed_codec:encode(Link, {value, 19}),
    [Reverse] = [L || L = #{source_index := 2, destination_index := 1} <- Links],
    {ReverseSlot, ReverseFrame} = hls_protocol_mixed_codec:encode(Reverse, {total, 9}),
    Command = {host, all, {1, 0, 1, 0}, {total, 12}},
    Control = hls_protocol_mixed_host:controls(Plan, Command),
    Event = hls_protocol_mixed_host:external(Plan, 1, right, {value, 23}),
    Module = hls_protocol_network_fixture,
    {Module, Original, Filename} = code:get_object_code(Module),
    try
        reload_codec_trap(Module),
        Retained = binary_to_term(term_to_binary(Plan)),
        ?assertEqual(ok, hls_protocol_mixed_codec:check(Retained)),
        ?assertEqual({Slot, Frame}, hls_protocol_mixed_codec:encode(Link, {value, 19})),
        ?assertEqual({Slot, Frame}, hls_protocol_mixed_codec:encode(Link, early, {value, 19})),
        ?assertEqual({value, 19}, hls_protocol_mixed_codec:decode(Link, Slot, Frame)),
        ?assertEqual({total, 9}, hls_protocol_mixed_codec:decode(Reverse, ReverseSlot, ReverseFrame)),
        ?assertEqual(Control, hls_protocol_mixed_host:controls(Retained, Command)),
        ?assertEqual(Event, hls_protocol_mixed_host:external(Retained, 1, right, {value, 23})),
        ?assertException(error, _, hls_protocol_mixed_host:external(Retained, 1, right, {go, 7}))
    after
        code:purge(Module),
        {module, Module} = code:load_binary(Module, Filename, Original)
    end.

%% Every actor codec entry raises, so retained bindings must use the generic record codec.
-spec reload_codec_trap(module()) -> ok.
reload_codec_trap(Module) ->
    Functions = [{pack, 1}, {unpack, 2}, {pack_tag, 1}, {pack_width, 1}],
    Forms = [{attribute, 1, module, Module}, {attribute, 1, export, Functions}] ++
        [{function, 1, Name, Arity, [{clause, 1, lists:duplicate(Arity, {var, 1, '_'}), [],
            [{call, 1, {remote, 1, {atom, 1, erlang}, {atom, 1, error}},
                [{atom, 1, reloaded_actor_codec_called}]}]}]} || {Name, Arity} <- Functions],
    {ok, Module, Bytes} = compile:forms(Forms, [binary, warnings_as_errors]),
    code:purge(Module),
    {module, Module} = code:load_binary(Module, "retained-codec-trap", Bytes),
    ok.
