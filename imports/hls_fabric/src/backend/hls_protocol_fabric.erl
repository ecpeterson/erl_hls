-module(hls_protocol_fabric).
-moduledoc "Connects source snapshots directly to fixed sender-local capture links. Actor scheduling and declared external input adapters remain separate, mandatory consumers of this transport interface.".
-export([plan/2]).

-doc "Binds every internal source output to exactly one logical sender/destination link and checks all typed widths and class indices. External outputs retain independent ordinary frames. Missing, duplicate or mismatched endpoints fail instead of introducing a generic route. The result does not establish actor lifetime, generation or network progress.".
-spec plan(map(),map()) -> map().
plan(#{sources:=Sources},Inbox=#{pairs:=Pairs}) ->
    Shapes=hls_protocol_link:components(Inbox),
    Links=[bind_link(I,P,Sources,Shapes)||{I,P}<-lists:enumerate(0,Pairs)],
    Internal=[{maps:get(index,S),maps:get(index,O)}||S<-Sources,O<-maps:get(outputs,S),
        {actor,_}<-[maps:get(destination,O)]],
    Bound=[{maps:get(source_index,L),maps:get(output_index,L)}||L<-Links],
    true=lists:sort(Internal)=:=lists:sort(Bound),
    true=length(Bound)=:=length(lists:usort(Bound)),
    Boundaries=[#{source_index=>I,output=>O}||#{index:=I,outputs:=Os}<-Sources,
        O=#{destination:={external,_},width:=128}<-Os],
    true=length(Boundaries)=:=length([O||S<-Sources,O<-maps:get(outputs,S),
        {external,_}<-[maps:get(destination,O)]]),
    #{sources=>Sources,links=>Links,boundaries=>Boundaries,
      whole_protocol_eligible=>false,ordering=>per_logical_sender_destination}.

%% The source projection and destination catalogue must identify the same logical message classes.
-spec bind_link(non_neg_integer(),map(),[map()],[map()]) -> map().
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
