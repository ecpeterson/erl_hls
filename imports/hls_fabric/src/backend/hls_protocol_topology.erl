-module(hls_protocol_topology).
-moduledoc "Materializes a bounded normalized topology while preserving its complete spatial ingress contract. Expansion is source bookkeeping, not protocol eligibility or hardware admission.".
-export([elaborate/2]).
-export_type([id/0, destination/0, actor/0, route/0, ingress/0, plan/0]).

-doc "A normalized static logical identity: atom, nonnegative integer or a nonempty tuple recursively containing those values.".
-type id() :: atom() | non_neg_integer() | tuple().

-doc "A logical actor or declared external recipient; neither is a process or transport endpoint.".
-type destination() :: {actor, id()} | {external, id()}.

-doc "One exact source actor after family expansion, retaining its declared outputs and mailbox bound.".
-type actor() :: #{id := id(), module := module(), outputs := [atom()], mailbox_capacity := pos_integer()}.

-doc "One complete source-port disposition with explicit fanout completion semantics.".
-type route() :: #{source := {id(), atom()}, recipients := [destination()],
    delivery := direct | coupled | buffered | queued | best_effort}.

-doc "One rectangle ingress with explicit actor coordinates and source-declared target schemas.".
-type ingress() :: #{id := id(), kind := rectangle, shape := [pos_integer()],
    targets := [#{id := id(), schemas := [atom()],
        recipients := [#{actor := id(), at := [non_neg_integer()]}]}]}.

-doc "A fully expanded source topology. Family/relation lists are empty, while startup order, external schemas, routes and ingress coordinates remain intact.".
-type plan() :: #{version := 1, actors := [actor()], families := [], routes := [route()],
    route_relations := [], lane_relations := [], ingresses := [ingress()],
    externals := [#{id := id(), direction := out, schemas := [atom()]}],
    startup := [#{target := id(), delivery := cast, messages := [tuple()]}],
    lanes := [#{source := id(), destination := destination(), source_ports := [atom()]}]}.

-doc "Expands checked two-dimensional rectangular families and their routes, retaining exact actors, startup, external streams, target schemas and spatial embedding. Limit bounds total actor count before enumeration. Every ingress recipient becomes an explicit actor and coordinate; multiple actors may share one coordinate, but a target may not address the same actor twice. Unknown families, unsupported shapes, duplicate ownership or invalid coordinates raise protocol_topology errors. The result still requires boundary, lifetime, ordering, capacity and progress qualification; it does not turn spatial multicast into atomic delivery.".
-spec elaborate(hls_topology:plan(), pos_integer()) -> plan().
elaborate(P=#{actors:=Exact,families:=Families,routes:=Routes,ingresses:=Ingresses},Limit)
        when is_integer(Limit),Limit>0,Limit=<65536 ->
    Count=length(Exact)+lists:sum([family_size(F)||F<-Families]),
    need(Count=<Limit,{actor_limit,Count,Limit}),
    FamilyMap=maps:from_list([{maps:get(id,F),F}||F<-Families]),
    need(map_size(FamilyMap)=:=length(Families),duplicate_family),
    Actors=Exact++lists:append([members(F)||F<-Families]),
    Ids=[maps:get(id,A)||A<-Actors],
    need(length(Ids)=:=length(lists:usort(Ids)),duplicate_actor),
    Expanded=Routes++lists:append([hls_topology:routes_for_instance(P,Id,[X,Y])
        ||#{id:=Id,shape:=[W,H]}<-Families,X<-lists:seq(0,W-1),Y<-lists:seq(0,H-1)]),
    Sources=[S||#{source:=S}<-Expanded],
    need(length(Sources)=:=length(lists:usort(Sources)),duplicate_source_port),
    Is=[ingress(I,FamilyMap,Ids)||I<-Ingresses],
    P#{actors:=Actors,families:=[],routes:=Expanded,ingresses:=Is,
       route_relations:=[],lane_relations:=[],lanes=>xls_topology_graph:lanes(Expanded)};
elaborate(_,Limit)->error({protocol_topology,{invalid_actor_limit,Limit}}).

%% Count before allocating actor or recipient arrays.
-spec family_size(map()) -> pos_integer().
family_size(#{shape:=[W,H]}) when is_integer(W),W>0,is_integer(H),H>0->W*H;
family_size(F)->error({protocol_topology,{unsupported_family_shape,maps:get(id,F,unknown)}}).

%% The ordinary topology's canonical coordinate identity is retained byte-for-byte.
-spec members(#{id := id(), module := module(), shape := [pos_integer()],
    instance_count := pos_integer(), outputs := [atom()], mailbox_capacity := pos_integer()}) -> [actor()].
members(F=#{id:=Id,shape:=[W,H]})->
    [maps:without([shape,instance_count],F#{id:={Id,X,Y}})||X<-lists:seq(0,W-1),Y<-lists:seq(0,H-1)].

%% Explicit coordinates retain the caller's rectangle semantics and all schema declarations.
-spec ingress(map(), map(), [id()]) -> ingress().
ingress(I=#{id:=Id,kind:=rectangle,shape:=[W,H],targets:=Ts},Families,Actors)->
    I#{targets:=[begin
        Rs=lists:append([recipient(R,Families)||R<-maps:get(recipients,T)]),
        Assigned=[A||#{actor:=A}<-Rs],
        need(length(Assigned)=:=length(lists:usort(Assigned)),{duplicate_ingress_recipient,Id,maps:get(id,T)}),
        lists:foreach(fun(#{actor:=A,at:=[X,Y]})->
            need(lists:member(A,Actors),{unknown_ingress_actor,Id,A}),
            need(X>=0 andalso X<W andalso Y>=0 andalso Y<H,{ingress_coordinate,Id,A,[X,Y]})
        end,Rs),
        T#{recipients:=Rs}
    end||T<-Ts]};
ingress(I,_,_)->error({protocol_topology,{unsupported_ingress,I}}).

%% Multiple distinct families can deliberately occupy the same physical control coordinate.
-spec recipient(map(), map()) -> [#{actor := id(), at := [integer()]}].
recipient(R=#{actor:=_,at:=[_,_]},_)->[R];
recipient(#{family:=Id,scale:=[SX,SY],offset:=[OX,OY]},Families)->
    case maps:find(Id,Families) of
      {ok,#{shape:=[W,H]}}->[#{actor=>{Id,X,Y},at=>[SX*X+OX,SY*Y+OY]}
          ||X<-lists:seq(0,W-1),Y<-lists:seq(0,H-1)];
      error->error({protocol_topology,{unknown_ingress_family,Id}})
    end;
recipient(R,_)->error({protocol_topology,{unsupported_ingress_recipient,R}}).

%% Report the specific missing checked input instead of falling back to generic hardware.
-spec need(boolean(),term()) -> ok.
need(true,_)->ok;
need(false,Reason)->error({protocol_topology,Reason}).
