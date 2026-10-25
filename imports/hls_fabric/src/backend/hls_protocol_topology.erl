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

-doc "Expands checked two-dimensional rectangular families and their routes, retaining exact actors, startup, external streams, target schemas and spatial embedding. Limit bounds total actor count before enumeration. Every ingress recipient becomes an explicit actor and coordinate; multiple actors may share one coordinate, but a target may not address the same actor twice. Unknown families, unsupported shapes, duplicate ownership or invalid coordinates raise topology diagnostics. The result still requires boundary, lifetime, ordering, capacity and progress qualification; it does not turn spatial multicast into atomic delivery.".
-spec elaborate(hls_topology:plan(), pos_integer()) -> plan().
elaborate(P=#{actors:=Exact,families:=Families,routes:=Routes,ingresses:=Ingresses},Limit)
        when is_integer(Limit),Limit>0,Limit=<65536 ->
    Count=length(Exact)+lists:sum([family_size(F)||F<-Families]),
    need(Count=<Limit,{actor_limit,Count,Limit}),
    FamilyMap=maps:from_list([{maps:get(id,F),F}||F<-Families]),
    need(map_size(FamilyMap)=:=length(Families),{duplicate_family,[maps:get(id,F)||F<-Families]}),
    Actors=Exact++lists:append([members(F)||F<-Families]),
    Ids=[maps:get(id,A)||A<-Actors],
    need(length(Ids)=:=length(lists:usort(Ids)),{duplicate_actor,Ids}),
    Expanded=Routes++lists:append([hls_topology:routes_for_instance(P,Id,[X,Y])
        ||#{id:=Id,shape:=[W,H]}<-Families,X<-lists:seq(0,W-1),Y<-lists:seq(0,H-1)]),
    Sources=[S||#{source:=S}<-Expanded],
    need(length(Sources)=:=length(lists:usort(Sources)),{duplicate_source_port,Sources}),
    Is=[hls_diagnostic:with_context(#{ingress=>maps:get(id,I,unknown)},
        fun() -> ingress(I,FamilyMap,Ids) end) || I<-Ingresses],
    P#{actors:=Actors,families:=[],routes:=Expanded,ingresses:=Is,
       route_relations:=[],lane_relations:=[],lanes=>xls_topology_graph:lanes(Expanded)};
elaborate(_,Limit)->reject({invalid_actor_limit,Limit}).

%% Count before allocating actor or recipient arrays.
-spec family_size(map()) -> pos_integer().
family_size(#{shape:=[W,H]}) when is_integer(W),W>0,is_integer(H),H>0->W*H;
family_size(F)->reject({unsupported_family_shape,maps:get(id,F,unknown),maps:get(shape,F,undefined)}).

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
ingress(I,_,_)->reject({unsupported_ingress,I}).

%% Multiple distinct families can deliberately occupy the same physical control coordinate.
-spec recipient(map(), map()) -> [#{actor := id(), at := [integer()]}].
recipient(R=#{actor:=_,at:=[_,_]},_)->[R];
recipient(#{family:=Id,scale:=[SX,SY],offset:=[OX,OY]},Families)->
    case maps:find(Id,Families) of
      {ok,#{shape:=[W,H]}}->[#{actor=>{Id,X,Y},at=>[SX*X+OX,SY*Y+OY]}
          ||X<-lists:seq(0,W-1),Y<-lists:seq(0,H-1)];
      error->reject({unknown_ingress_family,Id})
    end;
recipient(R,_)->reject({unsupported_ingress_recipient,R}).

%% Report the specific missing checked input instead of falling back to generic hardware.
-spec need(boolean(),term()) -> ok.
need(true,_)->ok;
need(false,Reason)->reject(Reason).

%% Only declared source-shape failures become diagnostics; unexpected invariants retain their stack.
-spec reject(term()) -> no_return().
reject(Reason) ->
    {Code,Message,Context}=diagnostic(Reason),
    hls_diagnostic:raise(topology,Code,Message,Context#{reason=>Reason}).

%% Keep source identities in context instead of embedding their printed form in messages.
-spec diagnostic(term()) -> {atom(),binary(),map()}.
diagnostic({actor_limit,Count,Limit}) ->
    {actor_limit,<<"The expanded topology exceeds the configured actor limit.">>,#{actual=>Count,maximum=>Limit}};
diagnostic({invalid_actor_limit,Limit}) ->
    {invalid_actor_limit,<<"The actor limit must be an integer from 1 through 65536.">>,#{value=>Limit,path=>[actor_limit]}};
diagnostic({duplicate_family,Ids}) ->
    {duplicate_family,<<"Topology family IDs must be unique.">>,#{families=>Ids}};
diagnostic({duplicate_actor,Ids}) ->
    {duplicate_actor,<<"Explicit and expanded actor IDs must be unique.">>,#{actors=>Ids}};
diagnostic({duplicate_source_port,Sources}) ->
    {duplicate_source_port,<<"Each actor output port must have one route declaration.">>,#{sources=>Sources}};
diagnostic({unsupported_family_shape,Id,Shape}) ->
    {unsupported_family_shape,<<"Protocol families require two positive rectangle dimensions.">>,#{family=>Id,shape=>Shape}};
diagnostic({duplicate_ingress_recipient,Ingress,Target}) ->
    {duplicate_ingress_recipient,<<"An ingress target may address each actor only once.">>,#{ingress=>Ingress,target=>Target}};
diagnostic({unknown_ingress_actor,Ingress,Actor}) ->
    {unknown_ingress_actor,<<"An ingress recipient must name an actor in the expanded topology.">>,#{ingress=>Ingress,actor=>Actor}};
diagnostic({ingress_coordinate,Ingress,Actor,At}) ->
    {ingress_coordinate,<<"Ingress coordinates must lie within the declared rectangle.">>,#{ingress=>Ingress,actor=>Actor,coordinate=>At}};
diagnostic({unsupported_ingress,Ingress}) ->
    {unsupported_ingress,<<"Protocol ingress requires a rectangle with explicit targets.">>,#{value=>Ingress}};
diagnostic({unknown_ingress_family,Id}) ->
    {unknown_ingress_family,<<"An ingress family recipient must name a declared family.">>,#{family=>Id}};
diagnostic({unsupported_ingress_recipient,Recipient}) ->
    {unsupported_ingress_recipient,<<"Use an actor coordinate or a family with scale and offset for each ingress recipient.">>,#{value=>Recipient}}.
