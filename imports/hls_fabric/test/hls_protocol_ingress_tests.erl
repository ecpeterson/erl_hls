-module(hls_protocol_ingress_tests).
-include_lib("eunit/include/eunit.hrl").

%% Full-width payloads stay unconstrained; malformed header and padding do not.
-spec schema_domain_test() -> ok.
schema_domain_test() ->
    A=artifact([work],u32),[#{mask:=M,value:=V}]=hls_protocol_schema:domains(A,[work]),
    [F]=hls_protocol_schema:frames(A,[{work,16#ffffffff}]),
    ?assertEqual(V,F band M),?assertNotEqual(V,(F bor (1 bsl 64)) band M),
    ?assertNotEqual(V,(F bxor (1 bsl 8)) band M),
    ?assertError({invalid_ingress_schemas,[]},hls_protocol_schema:domains(A,[])),
    ?assertError({invalid_ingress_schemas,[work,work]},hls_protocol_schema:domains(A,[work,work])),
    ?assertError({undeclared_protocol_schema,other},hls_protocol_schema:domains(A,[other])).

%% One shared command covers all selected actor identities without duplicating frames.
-spec binding_test() -> ok.
binding_test() ->
    B=bundle(),P=hls_protocol_ingress:plan(B),
    ?assertEqual(131,maps:get(state_bits,P)),
    ?assert(hls_protocol_ingress:addressed(P,0)),?assert(hls_protocol_ingress:addressed(P,1)),
    ?assertNot(hls_protocol_ingress:addressed(P,2)),?assertNot(hls_protocol_ingress:addressed(none,0)),
    #{topology:=T}=B,?assertEqual(none,hls_protocol_ingress:plan(B#{topology:=T#{ingresses:=[]}})).

%% Two individually valid destination schemas must agree on the actual operation number.
-spec mismatched_codec_test() -> ok.
mismatched_codec_test() ->
    B=bundle(),?assertError({incompatible_ingress_schemas,all},hls_protocol_ingress:plan(B#{modules:=#{a=>artifact([work],u32),b=>artifact([other,work],u32)}})),
    ?assertError({incompatible_ingress_schemas,all},hls_protocol_ingress:plan(B#{modules:=#{a=>artifact([work],u32),b=>artifact([work],s32)}})).

%% Missing schemas, duplicate recipients and unsupported boundaries fail before generation.
-spec rejects_ambiguous_test() -> ok.
rejects_ambiguous_test() ->
    B=#{topology:=T=#{ingresses:=[I=#{targets:=[Target=#{recipients:=[A|_]}]}]}}=bundle(),
    Check=fun(New)->hls_protocol_ingress:plan(B#{topology:=T#{ingresses:=[New]}}) end,
    ?assertError({ambiguous_ingress_recipients,all},Check(I#{targets:=[Target#{recipients:=[A,A]}]})),
    Missing=maps:remove(schemas,Target),
    ?assertError({invalid_ingress_target,Missing},Check(I#{targets:=[Missing]})),
    ?assertException(error,_,Check(I#{shape:=[65537,1]})),
    ?assertException(error,_,hls_protocol_ingress:plan(B#{topology:=T#{ingresses:=[I,I]}})).

%% Normalized topology is the same explicit source binding consumed by transport generation.
-spec bundle() -> map().
bundle() -> #{topology=>#{actors=>[#{id=>left,module=>a},#{id=>right,module=>b}],
    ingresses=>[#{id=>host,kind=>rectangle,shape=>[3,2],targets=>[
      #{id=>all,schemas=>[work],recipients=>[#{actor=>left,at=>[0,0]},#{actor=>right,at=>[2,1]}]}]}]},
    modules=>#{a=>artifact([work],u32),b=>artifact([work],u32)}}.

%% Minimal fresh-artifact-shaped schema retains ordinary AST field types and tag ordering.
-spec artifact([atom()],atom()) -> map().
artifact(Names,Type) -> #{spec=>#{message_names=>Names},plan=>#{records=>[
    {attribute,1,record,{Name,[{typed_record_field,{record_field,1,{atom,1,n}},
      {hls_record_type,1,{hls_type,hls_nums,Type,[]}}}]}}||Name<-Names]}}.
