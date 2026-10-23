-module(hls_protocol_ingress).
-moduledoc "Binds one declared rectangular host interface to fresh receiving schemas and dense actor identities. No fixture traffic or source-state facts define the wire domain.".
-export([plan/1, addressed/2]).

-doc "Plans zero or one rectangle ingress with one to four targets, each with nonempty explicit schemas and recipients. Every recipient of a target must have identical canonical encodings and ordered field names/types. Coordinates are inclusive within dimensions 1..65536. Rejects ambiguous recipients, incompatible encodings and unsupported shapes. Delivery uses the ordinary 194-bit SpatialFrame, one registered command, and independent per-actor consumption. One postponed head can block later host commands; this establishes neither capacity nor progress.".
-spec plan(map()) -> none | map().
plan(#{topology:=#{ingresses:=[]}}) -> none;
plan(#{topology:=#{actors:=Actors,ingresses:=[#{id:=Id,kind:=rectangle,shape:=[W,H],targets:=Targets}]},modules:=Modules})
        when W>0,W=<65536,H>0,H=<65536,length(Targets)>0,length(Targets)=<4 ->
    Bound=[target(T,K,Actors,Modules,W,H)||{K,T}<-lists:enumerate(0,Targets)],
    #{id=>Id,width=>W,height=>H,actors=>length(Actors),targets=>Bound,input_bits=>194,
      state_bits=>129+length(Actors),host_order=>one_command_until_all_selected_actors_consume,
      admission=>after_declared_startup_consumption,malformed=>sticky_fault_without_delivery,
      retirement=>source_consume,reset=>cancels_command_and_fault,capacity=>unestablished,network_progress=>unestablished};
plan(#{topology:=#{ingresses:=Ingresses}}) -> error({unsupported_protocol_ingress,Ingresses}).

-doc "Reports whether the checked plan addresses an actor index. Addressed receivers need exactly one host slot, shared by all targets because at most one host command is outstanding.".
-spec addressed(none | map(),non_neg_integer()) -> boolean().
addressed(none,_) -> false;
addressed(#{targets:=Targets},Index) ->
    lists:any(fun(#{recipients:=Rs})->lists:any(fun(#{index:=I})->I=:=Index end,Rs) end,Targets).

%% Different targets may reuse recipients; a target may not deliver duplicate copies.
-spec target(map(),non_neg_integer(),[map()],map(),pos_integer(),pos_integer()) -> map().
target(#{id:=Id,schemas:=Schemas,recipients:=Recipients},Selector,Actors,Modules,W,H) ->
    case Recipients of []->error({empty_ingress_target,Id}); _->ok end,
    Points=[begin
        case X>=0 andalso X<W andalso Y>=0 andalso Y<H of
            true->ok;false->error({ingress_coordinate,Id,[X,Y]})
        end,
        [{I,#{module:=M}}]=[{J,A}||{J,A=#{id:=Identity}}<-lists:enumerate(0,Actors),Identity=:=Actor],
        #{index=>I,x=>X,y=>Y,schemas=>lists:sort(hls_protocol_schema:domains(maps:get(M,Modules),Schemas))}
    end||#{actor:=Actor,at:=[X,Y]}<-Recipients],
    case length(Points)=:=length(Recipients) andalso length(Points)=:=length(lists:usort([I||#{index:=I}<-Points])) of
        true->ok;false->error({ambiguous_ingress_recipients,Id})
    end,
    case lists:usort([Fs||#{schemas:=Fs}<-Points]) of
        [Domains]->#{id=>Id,selector=>Selector,domains=>Domains,recipients=>[maps:remove(schemas,P)||P<-Points]};
        _->error({incompatible_ingress_schemas,Id})
    end;
target(Target,_,_,_,_,_) -> error({invalid_ingress_target,Target}).
