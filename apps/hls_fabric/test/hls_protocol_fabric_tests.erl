-module(hls_protocol_fabric_tests).
-moduledoc "Checks exact sender/recipient binding and rejects fabricated routing or payload contracts.".
-include_lib("eunit/include/eunit.hrl").

%% Two output ports of one logical sender share their single destination link.
-spec same_sender_binding_test() -> ok.
same_sender_binding_test() ->
    {Sources,Inbox}=fixture(),#{links:=[L]}=hls_protocol_fabric:plan(Sources,Inbox),
    ?assertEqual({0,1,2,48}, {maps:get(source_index,L),maps:get(destination_index,L),
        maps:get(slots,L),maps:get(payload_bits,L)}).

%% A source output without a corresponding destination lease cannot silently disappear.
-spec missing_link_test() -> ok.
missing_link_test() ->
    {Sources,_}=fixture(),?assertException(error,_,hls_protocol_fabric:plan(Sources,#{pairs=>[]})).

%% Two links cannot acquire the same source delivery independently.
-spec duplicate_link_test() -> ok.
duplicate_link_test() ->
    {Sources,#{pairs:=[P]}}=fixture(),
    ?assertException(error,_,hls_protocol_fabric:plan(Sources,#{pairs=>[P,P]})).

%% The sender's compact physical payload must cover exactly the destination's largest class.
-spec width_mismatch_test() -> ok.
width_mismatch_test() ->
    {#{sources:=[S,T]},Inbox}=fixture(),[O]=maps:get(outputs,S),
    ?assertException(error,_,hls_protocol_fabric:plan(#{sources=>[S#{outputs=>[O#{width=>31}]},T]},Inbox)).

%% Renaming an output port does not transfer another channel's ordering or storage authority.
-spec false_channel_test() -> ok.
false_channel_test() ->
    {#{sources:=[S,T]},Inbox}=fixture(),[O]=maps:get(outputs,S),[R|Rs]=maps:get(rows,O),
    ?assertException(error,_,hls_protocol_fabric:plan(#{sources=>[S#{outputs=>[O#{rows=>[R#{port=>wrong}|Rs]}]},T]},Inbox)).

%% A declared external stream is kept independently and retains the complete ordinary frame.
-spec boundary_frame_test() -> ok.
boundary_frame_test() ->
    {#{sources:=[S,T]},Inbox}=fixture(),Os=maps:get(outputs,S),
    External=#{index=>1,destination=>{external,host},offset=>32,width=>128,rows=>[]},
    #{boundaries:=[#{source_index:=0,output:=External}]}=hls_protocol_fabric:plan(
        #{sources=>[S#{outputs=>Os++[External]},T]},Inbox),ok.

%% The fixture has a logical sender, two physical source ports and two compact message classes.
-spec fixture() -> {map(),map()}.
fixture() ->
    Rows=[#{capture_slot=>0,port=>first,tag=>a},#{capture_slot=>1,port=>second,tag=>b}],
    Sources=#{sources=>[#{index=>0,actor=>sender,outputs=>[
        #{index=>0,destination=>{actor,receiver},width=>32,offset=>0,rows=>Rows}]},
        #{index=>1,actor=>receiver,outputs=>[]}]},
    Inbox=#{pairs=>[#{source=>sender,destination=>{actor,receiver},slots=>[
        #{index=>0,payload_bits=>32,channel=>#{port=>first,tag=>a}},
        #{index=>1,payload_bits=>16,channel=>#{port=>second,tag=>b}}]}]},
    {Sources,Inbox}.
