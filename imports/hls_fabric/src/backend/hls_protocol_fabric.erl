-module(hls_protocol_fabric).
-moduledoc "Connects source snapshots directly to fixed sender-local capture links. Actor scheduling and declared external input adapters remain separate, mandatory consumers of this transport interface.".
-export([plan/2]).
-export_type([link/0, boundary/0, plan/0]).

-doc "One sender/recipient capture link, with global actor/output indices and the exact per-class payload layout. Native partitioning may add crossing direction and destination codecs.".
-type link() :: #{index := non_neg_integer(), source_index := non_neg_integer(),
    destination_index := non_neg_integer(), output_index := non_neg_integer(),
    output := hls_protocol_source:output(), shape := non_neg_integer(), widths := [pos_integer()],
    slots := pos_integer(), payload_bits := pos_integer(), input_bits := pos_integer(),
    index_bits := pos_integer(), pair := hls_protocol_inbox:pair(),
    direction => incoming | outgoing, classes => [hls_protocol_partition:class()]}.

-doc "One ordinary-frame output to a declared external recipient, retaining its source actor index.".
-type boundary() :: #{source_index := non_neg_integer(), output := hls_protocol_source:output()}.

-doc "Connected publishers, capture links and external outputs. Native placement may retain a crossing catalogue; no temporal admission is implied.".
-type plan() :: #{frame_layout := hls_frame_layout:layout(), sources := [hls_protocol_source:source()], links := [link()], boundaries := [boundary()],
    whole_protocol_eligible := false, ordering := per_logical_sender_destination,
    crossings => [hls_protocol_partition:crossing()]}.

%% Width-equivalent pair instances share one structural link component.
-type shape() :: #{id := non_neg_integer(), widths := [pos_integer()], instances := [hls_protocol_inbox:pair()]}.

-doc "Binds every internal source output to exactly one logical sender/destination link and checks all typed widths and class indices. External outputs retain independent ordinary frames. Missing, duplicate or mismatched endpoints fail instead of introducing a generic route. The result does not establish actor lifetime, generation or network progress.".
-spec plan(hls_protocol_source:plan(), hls_protocol_inbox:plan()) -> plan().
plan(SourcePlan=#{sources:=Sources},Inbox=#{pairs:=Pairs}) ->
    FrameLayout=maps:get(frame_layout,SourcePlan,hls_frame_layout:default()),
    FrameLayout=maps:get(frame_layout,Inbox,FrameLayout),
    FrameBits=hls_frame_layout:frame_bits(FrameLayout),
    Shapes=hls_protocol_link:components(Inbox),
    Links=[bind_link(I,P,Sources,Shapes)||{I,P}<-lists:enumerate(0,Pairs)],
    Internal=[{maps:get(index,S),maps:get(index,O)}||S<-Sources,O<-maps:get(outputs,S),
        {actor,_}<-[maps:get(destination,O)]],
    Bound=[{maps:get(source_index,L),maps:get(output_index,L)}||L<-Links],
    true=lists:sort(Internal)=:=lists:sort(Bound),
    true=length(Bound)=:=length(lists:usort(Bound)),
    Boundaries=[#{source_index=>I,output=>O}||#{index:=I,outputs:=Os}<-Sources,
        O=#{destination:={external,_},width:=Width}<-Os,Width=:=FrameBits],
    true=length(Boundaries)=:=length([O||S<-Sources,O<-maps:get(outputs,S),
        {external,_}<-[maps:get(destination,O)]]),
    #{frame_layout=>FrameLayout,sources=>Sources,links=>Links,boundaries=>Boundaries,
      whole_protocol_eligible=>false,ordering=>per_logical_sender_destination}.

%% The source projection and destination catalogue must identify the same logical message classes.
-spec bind_link(non_neg_integer(), hls_protocol_inbox:pair(),
    [hls_protocol_source:source()], [shape()]) -> link().
bind_link(I,Pair=#{source:=Sender,destination:=Destination,slots:=Slots},Sources,Shapes) ->
    [#{index:=Source,outputs:=Outputs}]=[S||S=#{actor:=Id}<-Sources,Id=:=Sender],
    [#{index:=Target}]=[S||S=#{actor:=Id}<-Sources,Destination=:={actor,Id}],
    [Output=#{index:=Out,width:=Width,rows:=Rows}]=[O||O=#{destination:=D}<-Outputs,D=:=Destination],
    [#{id:=Shape,widths:=Widths}]=[C||C=#{instances:=Instances}<-Shapes,lists:member(Pair,Instances)],
    true=Width=:=lists:max(Widths),
    true=lists:all(fun(#{capture_slot:=K,port:=Port,tag:=Tag})->
        lists:any(fun(#{index:=N,channel:=#{port:=P,tag:=T}})->K=:=N andalso Port=:=P andalso Tag=:=T end,Slots)
    end,Rows),
    #{index=>I,source_index=>Source,destination_index=>Target,output_index=>Out,
      output=>Output,shape=>Shape,widths=>Widths,slots=>length(Slots),
      payload_bits=>lists:sum(Widths),input_bits=>Width,
      index_bits=>max(1,ceil(math:log2(length(Slots)))),pair=>Pair}.
