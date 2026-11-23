-module(hls_protocol_transactions_tests).
-include_lib("eunit/include/eunit.hrl").

%% Independent recipients need no serialized physical delivery rounds for an ordered source batch.
-spec independent_deliveries_test() -> ok.
independent_deliveries_test() ->
    B=batch([effect(0,p,x),effect(1,q,y)],[channel(p,left,x),channel(q,right,y)]),
    ?assertEqual([0,1],maps:get(logical_send_order,B)),
    ?assertEqual(1,maps:get(required_pair_sequence_depth,B)),
    ?assertEqual(2,maps:get(recipient_count,B)).

%% Two ports to one inbox retain the actor's original order, not the physical channel enumeration.
-spec shared_recipient_test() -> ok.
shared_recipient_test() ->
    B=batch([effect(1,q,y),effect(0,p,x)],[channel(q,inbox,y),channel(p,inbox,x)]),
    [#{effects:=E}]=maps:get(per_recipient,B),
    ?assertEqual([p,q],[P || #{port:=P}<-E]),
    ?assertEqual(2,maps:get(required_pair_sequence_depth,B)).

%% A broadcast and a later unicast share order only at the overlapping destination.
-spec overlapping_fanout_test() -> ok.
overlapping_fanout_test() ->
    B=batch([effect(0,p,x),effect(1,q,y)],
        [channel(p,left,x),channel(p,right,x),channel(q,right,y)]),
    ?assertEqual([{left,1},{right,2}],
        [{D,length(E)} || #{destination:={actor,D},effects:=E}<-maps:get(per_recipient,B)]).

%% The snapshot captures shared source bits once, including overlap and partially known fields.
-spec snapshot_sharing_test() -> ok.
snapshot_sharing_test() ->
    F=effect(0,p,x),G=effect(1,q,y),
    A=F#{fields:=[#{name=>a,offset=>0,slices=>[{0,4}]}]},
    B=G#{fields:=[#{name=>b,offset=>2,slices=>[{0,4}]},#{name=>fixed,constant=><<7>>}]},
    #{capture:=C}=batch([A,B],[channel(p,left,x),channel(q,right,y)]),
    ?assertEqual(6,maps:get(distinct_dynamic_bits,C)),
    ?assertEqual(1,maps:get(constant_field_uses,C)),
    ?assertEqual(after_every_selected_recipient_accepts,maps:get(release,C)).

%% Incomplete producer coverage must not silently turn a source send into a no-op.
-spec missing_route_test() -> ok.
missing_route_test() -> ?assertError({badmatch,false},batch([effect(0,p,x)],[])).

%% Duplicate source bindings cannot cause duplicate delivery to the same actor.
-spec duplicate_route_test() -> ok.
duplicate_route_test() ->
    C=channel(p,left,x),?assertError({badmatch,false},batch([effect(0,p,x)],[C,C])).

%% Distinct runtime layouts remain alternatives, not one combined reservation footprint.
-spec layout_selection_test() -> ok.
layout_selection_test() ->
    A=effect(0,p,x),B=(effect(0,q,y))#{layout:=1},
    #{actors:=[#{batches:=Bs}]}=plan([A,B],[channel(p,left,x),channel(q,right,y)]),
    ?assertEqual([0,1],[L || #{layout:=L}<-Bs]),
    ?assertEqual([1,1],[N || #{delivery_count:=N}<-Bs]).

%% An empty branch still releases its transaction; it is not erased by the absence of effects.
-spec empty_layout_test() -> ok.
empty_layout_test() ->
    E=effect(0,p,x),
    I=#{actors=>[#{id=>a,module=>m}],channels=>[channel(p,left,x)],
        modules=>#{m=>#{entry_layouts=>[#{phase=>active,layout=>0},#{phase=>active,layout=>1}]}}},
    #{actors:=[#{batches:=Bs}]}=hls_protocol_transactions:plan(I,#{a=>[E]}),
    [Empty]=[B || B=#{layout:=1}<-Bs],
    ?assertEqual(0,maps:get(delivery_count,Empty)),
    ?assertEqual(0,maps:get(distinct_dynamic_bits,maps:get(capture,Empty))).

%% Minimal source-shaped fixtures avoid relying on the measured application's routing names.
-spec effect(non_neg_integer(),atom(),atom()) -> map().
effect(I,P,T) -> #{phase=>active,layout=>0,order=>I,port=>P,tag=>T,fields=>[]}.

%% The logical actor identity is independent of its physical output port.
-spec channel(atom(),atom(),atom()) -> map().
channel(P,D,T) -> #{source=>a,port=>P,tag=>T,destination=>{actor,D}}.

%% Every fixture retains an explicit source actor and complete instance alternatives.
-spec plan([map()],[map()]) -> map().
plan(E,C) ->
    Layouts=lists:usort([maps:with([phase,layout],X) || X<-E]),
    hls_protocol_transactions:plan(#{actors=>[#{id=>a,module=>m}],channels=>C,
        modules=>#{m=>#{entry_layouts=>Layouts}}},#{a=>E}).

%% Return the sole batch for assertions that are not about alternative selection.
-spec batch([map()],[map()]) -> map().
batch(E,C) -> #{actors:=[#{batches:=[B]}]}=plan(E,C),B.
