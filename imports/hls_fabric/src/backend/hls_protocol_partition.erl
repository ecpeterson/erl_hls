-module(hls_protocol_partition).
-moduledoc "Cuts a freshly compiled source network at logical actor boundaries. Crossing frames use destination schemas; physical framing, clock crossing and independent reset retirement remain adapter obligations.".
-export([plan/5]).
-export_type([class/0, crossing/0, plan/0]).

-doc "One crossing slot and its codec derived from the destination's fresh message schema.".
-type class() :: #{slot := non_neg_integer(), channel := hls_protocol_capture:binding(),
    codec := hls_protocol_codec:plan()}.

-doc "A global capture link crossing the selected native actor set. plan/5 adds direction and classes to the fabric link; its global indices remain unchanged.".
-type crossing() :: hls_protocol_fabric:link().

-doc "A checked native placement: selected actor indices, destination-owned links and the projected host ingress.".
-type plan() :: #{fabric := hls_protocol_fabric:plan(), ingress := none | hls_protocol_control:plan(),
    indices := [non_neg_integer()]}.

%% Other transport options belong to their owning planners and are ignored by this cut.
-type options() :: #{native_actors => [hls_protocol_topology:id()], atom() => term()}.

-doc "Selects all actors by default, or a nonempty proper subset of unique logical IDs in native_actors. Keeps global actor/link indices, local publications and destination-owned captures; crossing links carry a slot and canonical destination frame in the common source-build layout. Derives every codec from fresh capture/source schemas, never supplied constants. Filters rectangle recipients without renumbering the host mask. Returns fabric, ingress and native indices; malformed selections fail before hardware emission. All roles must share clock/reset and stable ready/valid handshakes. No capacity, progress or multi-board admission is established.".
-spec plan(options(), hls_protocol_transport:bundle(), hls_protocol_capture:plan(),
    hls_protocol_fabric:plan(), none | hls_protocol_control:plan()) -> plan().
plan(Config,Bundle=#{topology:=#{actors:=Actors}},Capture,Fabric=#{sources:=Sources,links:=Links,boundaries:=Boundaries},Ingress) ->
    Indexed=lists:enumerate(0,Actors),
    case maps:find(native_actors,Config) of
        error->#{fabric=>Fabric,ingress=>Ingress,indices=>[I||{I,_}<-Indexed]};
        {ok,Ids}->
            Known=[Id||#{id:=Id}<-Actors],
            case is_list(Ids) andalso Ids=/=[] andalso length(Ids)<length(Known)
                andalso length(Ids)=:=length(lists:usort(Ids)) andalso Ids--Known=:=[] of
                true -> ok;
                false -> hls_diagnostic:raise(placement, invalid_native_actors,
                    <<"native_actors must name a nonempty, unique proper subset of source actors.">>,
                    #{path => [native_actors], value => Ids, known_actors => Known})
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
            #{fabric=>Cut,ingress=>hls_protocol_control:project(Ingress,Native),indices=>Native}
    end.

%% Destination operation numbering may differ from the sender's numbering.
-spec classes(hls_protocol_fabric:link(), hls_protocol_transport:bundle(),
    hls_protocol_capture:plan()) -> [class()].
classes(#{destination_index:=D,pair:=#{slots:=Slots}},#{topology:=#{actors:=Actors},modules:=Modules},#{channels:=Channels}) ->
    #{module:=M}=lists:nth(D+1,Actors),
    #{program:=Program}=maps:get(M,Modules),
    #{message_names:=Names,frame_layout:=FrameLayout}=xls_actor_program:spec(Program),
    [begin
        [Channel]=[Ch||Ch<-Channels,maps:with([source,destination,port,tag],Ch)=:=C],
        [Op]=[O||{O,T}<-lists:enumerate(3,Names),T=:=maps:get(tag,C)],
        #{slot=>I,channel=>C,codec=>hls_protocol_codec:plan(Channel,Op,FrameLayout)}
    end||#{index:=I,channel:=C}<-Slots].
