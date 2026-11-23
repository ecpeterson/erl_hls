-module(hls_protocol_boundary_tests).
-moduledoc "The public boundary builder preserves canonical endpoint identities and exact producer membership.".
-include_lib("eunit/include/eunit.hrl").
-export([topology/0]).

%% Exercise integer, numeric atom and tuple IDs through source compilation and JSON emission.
-spec endpoint_identity_test() -> ok.
endpoint_identity_test() ->
    Path=filename:join("_build","boundary-identities-"++integer_to_list(erlang:system_time(nanosecond))),
    Manifest=hls_protocol_boundary:write(#{sources=>[{"apps/hls_fabric/test/hls_protocol_boundary_fixture.erl",[]},{?FILE,[]}],
        topology=>{?MODULE,topology,[]},actor_limit=>4},Path),
    #{externals:=Groups,arbitration_state_bits:=5,activation:=automatic}=Manifest,
    ?assertEqual([{0,<<"3">>,1},{1,<<"'3'">>,0},{2,<<"{bucket,1}">>,3}],
        [{I,Id,length(Ms)}||#{index:=I,id:=Id,members:=Ms}<-Groups]),
    {ok,Bytes}=file:read_file(filename:join(Path,"boundary/manifest.json")),
    ?assertEqual([<<"3">>,<<"'3'">>,<<"{bucket,1}">>],[maps:get(<<"id">>,E)||E<-maps:get(<<"externals">>,json:decode(Bytes))]),
    ?assertEqual([{0,2},{1,2},{2,2},{3,0}],lists:sort([{S,I}||#{index:=I,members:=Ms}<-Groups,#{source_index:=S}<-Ms])),
    ok.

-doc "Returns the ordinary fixture with valid non-string topology IDs, keeping actor behavior unchanged.".
-spec topology() -> map().
topology() ->
    T=#{externals:=Externals,routes:=Routes}=hls_protocol_boundary_fixture:topology(),
    Ids=#{shared=>{bucket,1},single=>3,unused=>'3'},
    T#{externals:=[{maps:get(Id,Ids),Direction,Schemas}||{Id,Direction,Schemas}<-Externals],
       routes:=[{From,[{external,maps:get(Id,Ids)}]}||{From,[{external,Id}]}<-Routes]}.
