-module(hls_protocol_application_tests).
-moduledoc "Fresh application bindings retain exact endpoint identities and the shared host command ABI.".
-include_lib("eunit/include/eunit.hrl").
-export([collision/0]).

%% No build should start when the caller requests an incompatible activation mode.
-spec invalid_mode_test() -> ok.
invalid_mode_test() ->
    ?assertError({application_requires_explicit_start,automatic},
        hls_protocol_application:write(#{device=>board,host=>1,activation=>automatic},"unused")),
    ?assertError(function_clause,hls_protocol_application:write(#{device=>board,host=>65536},"unused")).

%% The production builder, not a hand-assembled host map, supplies the command and event binding.
-spec binding_test() -> ok.
binding_test() ->
    Path=filename:join("_build","application-binding-"++integer_to_list(erlang:system_time(nanosecond))),
    D=#{devices:=#{board:=B},eligible:=false}=hls_protocol_application:write(
        #{sources=>[{"test/hls_protocol_boundary_fixture.erl",[]},{"test/hls_protocol_boundary_tests.erl",[]}],
          topology=>{hls_protocol_boundary_tests,topology,[]},actor_limit=>4,device=>board,host=>19},Path),
    #{activation:=explicit_start,identity:=Identity,events:=Events}=B,
    ?assertEqual(32,byte_size(Identity)),
    ?assertEqual([3,'3',{bucket,1}],[Id||{_,#{id:=Id}}<-lists:sort(maps:to_list(Events))]),
    ?assertMatch([{board,{19,7},{3,0,0},<<0:32>>}],hls_partition_wire:command(D,start)),
    ?assertMatch([{board,{19,7},{2,0,0},_}],hls_partition_wire:command(D,{host,cells,{0,0,3,0},{work,12}})),
    ?assertEqual({{bucket,1},{sample,2,12}},hls_partition_wire:event(B,{10,19},{5,0,0},<<2:32/little,12:32/little>>)),
    ?assertError({badmatch,false},hls_partition_wire:event(B,{10,19},{5,0,0},<<2:32/little>>)),
    {ok,Bytes}=file:read_file(filename:join(Path,"deployment.etf")),
    ?assertEqual(D,binary_to_term(Bytes)),ok.

%% Equal payload width and selector cannot conceal a reversed source record layout.
-spec external_collision_test() -> ok.
external_collision_test() ->
    Path=filename:join("_build","application-collision-"++integer_to_list(erlang:system_time(nanosecond))),
    ?assertError({ambiguous_application_event,shared,5},hls_protocol_application:write(
        #{sources=>[{"test/hls_protocol_boundary_fixture.erl",[]},{"test/hls_protocol_application_conflict.erl",[]},{?FILE,[]}],
          topology=>{?MODULE,collision,[]},actor_limit=>5,device=>board,host=>1},Path)),
    ?assertNot(filelib:is_dir(Path)).

-doc "Adds one equal-width but incompatible producer to the shared external endpoint.".
-spec collision() -> map().
collision() ->
    T=#{actors:=Actors,routes:=Routes}=hls_protocol_boundary_fixture:topology(),
    T#{actors:=Actors#{conflict=>hls_protocol_application_conflict},
       routes:=Routes++[{{conflict,monitor},[{external,shared}]}]}.

%% Program text stays fixed across applications; only typed configuration values change.
-spec gateway_configuration_test() -> ok.
gateway_configuration_test() ->
    Hardware = hls_protocol_control:framed(#{kind => rectangle, input_bits => 194}, #{}),
    Binding = #{identity => <<1:64/little, 2:64/little, 3:64/little, 4:64/little>>,
        host => 19, control => 7, events => #{0 => event}, control_adapter => Hardware},
    First = xls_protocol_application:emit(Binding),
    Second = xls_protocol_application:emit(Binding#{host := 65535, events := #{0 => a, 1 => b}}),
    {ok, Source} = file:read_file(filename:join(code:priv_dir(hls_fabric),
        "xls/templates/protocol_application.x")),
    ?assertEqual(Source, maps:get("gateway.x", First)),
    ?assertEqual(Source, maps:get("gateway.x", Second)),
    Config = iolist_to_binary(maps:get("application_config.x", First)),
    lists:foreach(fun(Declaration) -> ?assertNotEqual(nomatch, binary:match(Config, Declaration)) end,
        [<<"pub const EVENTS = u32:1;">>, <<"pub const ID0 = u64:1;">>,
         <<"pub const ID3 = u64:4;">>, <<"pub const HOST = u16:19;">>,
         <<"pub const CONTROL = u16:7;">>]),
    ?assertNotEqual(Config, iolist_to_binary(maps:get("application_config.x", Second))).
