-module(hls_protocol_source).
-moduledoc "Plans complete source entry batches and independent typed recipient outputs. The plan still requires connected receive, capacity and progress qualification.".
-export([plan/3]).

-doc "Binds every source batch to exact ordinary frame projections and declared typed capture channels. Outputs to one recipient keep their source order across ports; separate recipients have independent backpressure. Internal constant omissions retain explicit source-invariant requirements. This plan does not authorize eliminating receipt guards or establish a safe whole-network capacity.".
-spec plan(map(),map(),map()) -> map().
plan(#{topology:=#{actors:=Actors},modules:=Modules},#{actors:=Transactions},Capture) ->
    #{pairs:=Pairs}=hls_protocol_inbox:plan(Capture),
    Components=[begin
        [Transaction]=[T||T=#{actor:=A}<-Transactions,A=:=Id],
        #{spec:=Spec}=maps:get(M,Modules),
        actor(I,Id,Spec,Transaction,Capture,Pairs)
    end || {I,#{id:=Id,module:=M}}<-lists:enumerate(0,Actors)],
    #{sources=>Components,snapshot=>ordinary_evaluated_payload_and_layout,
      no_cross_sender_chronology=>true,whole_protocol_eligible=>false}.

%% Original layout payloads are retained once; their width includes shared dynamic fields.
-spec actor(non_neg_integer(),term(),map(),map(),map(),[map()]) -> map().
actor(I,Id,Spec,#{batches:=Batches},Capture,Pairs) ->
    Projection=hls_protocol_projection:plan(Spec),#{payload_width:=Width,rows:=Effects}=Projection,
    Destinations=lists:usort([D || #{per_recipient:=Rs}<-Batches,#{destination:=D}<-Rs]),
    Depth=lists:max([0|[N || #{required_pair_sequence_depth:=N}<-Batches]]),
    Slots=max(1,Depth),
    {Outputs,Total}=lists:mapfoldl(fun({D,Destination},At)->
        Rows=lists:append([recipient_rows(Id,Destination,B,Effects,Capture,Pairs)||B<-Batches]),
        OutputWidth=lists:max([1|[length(Bits)||#{bits:=Bits}<-Rows]]),
        {#{index=>D,destination=>Destination,offset=>At,width=>OutputWidth,rows=>Rows},At+OutputWidth}
    end,0,lists:enumerate(0,Destinations)),
    Masks=[#{layout=>L,mask=>lists:foldl(fun(#{index:=D,rows:=Rows},Mask)->
        lists:foldl(fun(#{layout:=RL,sequence:=K},M)->
            case RL=:=L of true->M bor (1 bsl (D*Slots+K));false->M end
        end,Mask,Rows)
    end,0,Outputs)} || #{layout:=L}<-Batches],
    true=length(Masks)=:=length(lists:usort([L||#{layout:=L}<-Masks])),
    #{index=>I,actor=>Id,payload_width=>Width,snapshot_width=>Width+8,
      destinations=>max(1,length(Destinations)),logical_destinations=>length(Destinations),
      sequence_slots=>Slots,outputs=>Outputs,output_width=>max(1,Total),masks=>Masks,
      same_sender_order=>one_snapshot_and_per_recipient_subsequence,
      invariant_scope=>source_bound_constant_omissions_not_runtime_input_validation}.

%% One physical output covers one logical destination, including all of its source ports.
-spec recipient_rows(term(),term(),map(),[map()],map(),[map()]) -> [map()].
recipient_rows(Source,Destination,#{layout:=Layout,deliveries:=Deliveries},Effects,Capture,Pairs) ->
    Selected=[D||D=#{destination:=Target}<-Deliveries,Target=:=Destination],
    [begin
        [#{frame:=Frame}]=[E||E=#{layout:=L,index:=N,port:=P,tag:=T}<-Effects,
            L=:=Layout,N=:=Order,P=:=Port,T=:=Tag],
        maps:merge(#{layout=>Layout,sequence=>K,source_order=>Order,port=>Port,tag=>Tag},
            projection(Source,Destination,Port,Tag,Frame,Capture,Pairs))
    end || {K,#{order:=Order,port:=Port,tag:=Tag}}<-lists:enumerate(0,Selected)].

%% Boundary recipients retain ordinary frames; internal links omit only certified source constants.
-spec projection(term(),term(),atom(),atom(),[hls_protocol_projection:bit()],map(),[map()]) -> map().
projection(_, {external,_},_,_,Frame,_,_) ->
    #{bits=>Frame,capture_slot=>0,constant_requirements=>[]};
projection(Source,Destination,Port,Tag,Frame,#{channels:=Channels},Pairs) ->
    [C]=[C0||C0=#{source:=S,destination:=D,port:=P,tag:=T}<-Channels,
        S=:=Source,D=:=Destination,P=:=Port,T=:=Tag],
    %% Operation comes from the complete ordinary projection and must be constant.
    OpBits=lists:sublist(Frame,25,8),true=lists:all(fun(B)->B=:=0 orelse B=:=1 end,OpBits),
    Op=hls_protocol_projection:evaluate(OpBits,0),
    #{frame_positions:=Positions,mask:=Mask,value:=Value}=hls_protocol_codec:plan(C,Op),
    Requirements=lists:filtermap(fun(J)->
        Expected=(Value bsr J) band 1,Actual=lists:nth(J+1,Frame),
        case (Mask bsr J) band 1 of
            0->false;
            1->case Actual of Expected->false;{payload,_}->{true,{Actual,Expected}};
                _->error({inconsistent_static_channel,Source,Destination,Port,Tag,J}) end
        end
    end,lists:seq(0,127)),
    [#{slots:=PairSlots}]=[P||P=#{source:=S,destination:=D}<-Pairs,S=:=Source,D=:=Destination],
    [Index]=[N||#{index:=N,channel:=#{port:=P,tag:=T}}<-PairSlots,P=:=Port,T=:=Tag],
    Bits=case Positions of []->[0];_->[lists:nth(J+1,Frame)||J<-Positions] end,
    #{bits=>Bits,capture_slot=>Index,constant_requirements=>lists:usort(Requirements)}.
