-module(hls_protocol_bridge_wire).
-moduledoc "Common-broker framing for a session-bound source partition. Build identity, sender binding, credits and actual BEAM admission remain the session owner's obligations.".
-export([attach/2, command/2, packet/1, event/3]).

-doc "Encodes a fresh nonzero session and exact 32-byte build identity. Attachment does not activate the application; await the matching attached response before setup.".
-spec attach(binary(),pos_integer()) -> {hls_fabric:header(),binary()}.
attach(Identity,Session) when byte_size(Identity)=:=32,Session>0,Session<(1 bsl 64)->
    {{1,0,0},<<Session:64/little,Identity/binary>>}.

-doc "Encodes explicit start or the bound application control payload with a session prefix. Control bytes must come from the deployment adapter (currently the hls_partition_wire rectangle ABI). The transport only enforces its word capacity; the bound hardware adapter and native capture validate command meaning.".
-spec command(pos_integer(),start|binary()) -> {hls_fabric:header(),binary()}.
command(Session,start) when Session>0,Session<(1 bsl 64)->{{3,0,0},<<Session:64/little,0:32>>};
command(Session,Control) when Session>0,Session<(1 bsl 64),byte_size(Control)>=4,
        byte_size(Control)=<32,byte_size(Control) rem 4=:=0 ->
    {{2,0,0},<<Session:64/little,Control/binary>>}.

-doc "Encodes one reserved actor data packet or exact host-admission ACK. Sequence exhaustion, link/slot bounds and zero ACK payload are checked before writing. This does not reserve credits or authorize replay.".
-spec packet(map()) -> {hls_fabric:header(),binary()}.
packet(#{kind:=Kind,session:=Session,sequence:=Seq,link:=Link,slot:=Slot,frame:=Frame})
        when (Kind=:=1 orelse Kind=:=2),Session>0,Session<(1 bsl 64),Seq>=0,Seq<16#ffffffff,
             Link>=0,Link<65536,Slot>=0,Slot<256,Frame>=0,Frame<(1 bsl 128),
             (Kind=:=1 orelse Frame=:=0) ->
    Value=(Kind bsl 248) bor (Session bsl 184) bor (Seq bsl 152) bor (Link bsl 136) bor (Slot bsl 128) bor Frame,
    {{4,0,0},<<Value:256/little>>}.

-doc "Decodes a complete broker frame after the owner checks its reserved route. Exact session rejects stale management and external events. Actor sequence, kind, route, credit and canonical payload checks belong to the source-bound queue/session owner; the transport envelope alone is not authentication.".
-spec event(pos_integer(),hls_fabric:header(),binary()) -> attached|started|{packet,map()}|{external,byte(),non_neg_integer()}.
event(Session,{16#81,0,0},<<Session:64/little>>) -> attached;
event(Session,{16#83,0,0},<<Session:64/little,0:32>>) -> started;
event(Session,{16#84,0,0},<<Value:256/little>>) ->
    <<Kind:8,Session:64,Seq:32,Link:16,Slot:8,Frame:128>> = <<Value:256>>,
    true=(Kind=:=1 orelse Kind=:=2) andalso Seq<16#ffffffff,
    true=Kind=:=1 orelse Frame=:=0,
    {packet,#{kind=>Kind,session=>Session,sequence=>Seq,link=>Link,slot=>Slot,frame=>Frame}};
event(Session,{16#85,Index,0},<<Session:64/little,Frame:128/little>>) -> {external,Index,Frame}.
