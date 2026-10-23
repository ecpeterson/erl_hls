-module(hls_protocol_startup_peer).
-moduledoc "Ordinary source relay supplies observable acknowledgments for the startup network witness.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1, idle/3, replying/3]).
-hls_data(cell).
-hls_phases([idle,replying]).
-hls_outputs([reply]).
-hls_tags([receipt,ack]).
-hls_mailbox_capacity(4).

%% Each entry retains the received payload until its complete batch is accepted.
-record(cell,{n=hls_type:zero() :: hls_nums:u32()}).
%% The schema agrees with the independently compiled producer's ordinary frame.
-record(receipt,{n=hls_type:zero() :: hls_nums:u32()}).
%% The response is both externally visible and returned to the initiating actor.
-record(ack,{n=hls_type:zero() :: hls_nums:u32()}).

-doc "Waits silently until the first source receipt.".
-spec init([]) -> {ok,idle,#cell{}}.
init([]) -> {ok,idle,#cell{}}.

-doc "Consumes the first receipt and enters the reply phase.".
-spec idle(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#receipt{},#cell{}) -> hls_statem:cast_result(#cell{}).
idle(enter,_,C) -> {C,[]};
idle(cast,#receipt{n=N},C) -> {replying,C#cell{n=N},consume}.

-doc "Publishes one acknowledgment per receipt in sender order.".
-spec replying(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#receipt{},#cell{}) -> hls_statem:cast_result(#cell{}).
replying(enter,_,C) -> {C,[{cast,reply,#ack{n=C#cell.n}}]};
replying(cast,#receipt{n=N},C) -> {repeat_phase,C#cell{n=N},consume}.
