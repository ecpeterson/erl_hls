-module(hls_protocol_application_conflict).
-moduledoc "A producer with reversed sample field names tests ambiguous shared external codec rejection.".
-behaviour(hls_statem).
-compile({parse_transform,hls_pack}).
-export([init/1,ready/3]).
-hls_data(cell).
-hls_phases([ready]).
-hls_outputs([monitor]).
-hls_tags([cfg,work,sample]).
-hls_mailbox_capacity(4).

%% Only a finite dummy source state is needed to bind this incompatible output schema.
-record(cell,{value=hls_type:zero() :: hls_nums:u32()}).
%% Same selector/width as the ordinary fixture's configuration.
-record(cfg,{id=hls_type:zero() :: hls_nums:u32()}).
%% Same selector/width as the ordinary fixture's work command.
-record(work,{base=hls_type:zero() :: hls_nums:u32()}).
%% Same selector and total width, but reversed semantic field order.
-record(sample,{seq=hls_type:zero() :: hls_nums:u32(),id=hls_type:zero() :: hls_nums:u32()}).

-doc "Starts in the one publishing phase.".
-spec init([]) -> {ok,ready,#cell{}}.
init([]) -> {ok,ready,#cell{}}.

-doc "Publishes one sample and consumes only the declared harmless host records.".
-spec ready(enter,hls_statem:phase(),#cell{}) -> hls_statem:enter_result(#cell{});
    (cast,#cfg{} | #work{},#cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter,_,C) -> {C,[{cast,monitor,#sample{seq=1,id=1}}]};
ready(cast,#cfg{},C) -> {ready,C,consume};
ready(cast,#work{},C) -> {ready,C,consume}.
