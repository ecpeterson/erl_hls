-module(hls_protocol_partition).
-moduledoc "Cuts a freshly compiled source network at logical actor boundaries. Crossing frames use destination schemas; physical framing, clock crossing and independent reset retirement remain adapter obligations.".
-export([plan/5]).

-doc "Selects all actors by default, or a nonempty proper subset of unique logical IDs in native_actors. Keeps global actor/link indices, local publications and destination-owned captures; crossing links carry a slot and canonical 128-bit destination frame. Derives every codec from fresh capture/source schemas, never supplied constants. Filters rectangle recipients without renumbering the host mask. Returns fabric, ingress and native indices; malformed selections fail before hardware emission. All roles must share clock/reset and stable ready/valid handshakes. No capacity, progress or multi-board admission is established.".
-spec plan(map(),map(),map(),map(),none | map()) -> map().
plan(Config,Bundle=#{topology:=#{actors:=Actors}},Capture,Fabric=#{sources:=Sources,links:=Links,boundaries:=Boundaries},Ingress) ->
    Indexed=lists:enumerate(0,Actors),
    case maps:find(native_actors,Config) of
        error->#{fabric=>Fabric,ingress=>Ingress,indices=>[I||{I,_}<-Indexed]};
        {ok,Ids}->
            Known=[Id||#{id:=Id}<-Actors],
            case is_list(Ids) andalso Ids=/=[] andalso length(Ids)<length(Known)
                andalso length(Ids)=:=length(lists:usort(Ids)) andalso Ids--Known=:=[] of
                true->ok;false->error({invalid_native_actors,Ids})
            end,
            Native=[I||{I,#{id:=Id}}<-Indexed,lists:member(Id,Ids)],
            Cross=[L#{direction=>case lists:member(S,Native) of true->outgoing;false->incoming end,
                    classes=>classes(L,Bundle,Capture)}
                ||L=#{source_index:=S,destination_index:=D}<-Links,
                    lists:member(S,Native)=/=lists:member(D,Native)],
            LocalLinks=[case [C||C=#{index:=J}<-Cross,J=:=I] of []->L;[C]->C end
                ||L=#{index:=I,destination_index:=D}<-Links,lists:member(D,Native)],
            Cut=Fabric#{sources:=[S||S=#{index:=I}<-Sources,lists:member(I,Native)],links:=LocalLinks,
                boundaries:=[B||B=#{source_index:=I}<-Boundaries,lists:member(I,Native)],crossings=>Cross},
            #{fabric=>Cut,ingress=>ingress(Ingress,Native),indices=>Native}
    end.

%% Destination operation numbering may differ from the sender's numbering.
-spec classes(map(),map(),map()) -> [map()].
classes(#{destination_index:=D,pair:=#{slots:=Slots}},#{topology:=#{actors:=Actors},modules:=Modules},#{channels:=Channels}) ->
    #{module:=M}=lists:nth(D+1,Actors),
    #{program:=Program}=maps:get(M,Modules),
    #{message_names:=Names}=xls_actor_program:spec(Program),
    [begin
        [Channel]=[Ch||Ch<-Channels,maps:with([source,destination,port,tag],Ch)=:=C],
        [Op]=[O||{O,T}<-lists:enumerate(3,Names),T=:=maps:get(tag,C)],
        #{slot=>I,channel=>C,codec=>hls_protocol_codec:plan(Channel,Op)}
    end||#{index:=I,channel:=C}<-Slots].

%% Global mask indices survive holes; a target may address no actor on this role.
-spec ingress(none | map(),[non_neg_integer()]) -> none | map().
ingress(none,_) -> none;
ingress(Ingress=#{targets:=Targets},Native) ->
    Ingress#{targets:=[T#{recipients:=[R||R=#{index:=I}<-Rs,lists:member(I,Native)]}
        ||T=#{recipients:=Rs}<-Targets]}.
