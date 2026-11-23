-module(hls_protocol_frame_fixture).
-moduledoc "Small source schemas for independent frame-width and canonical-padding witnesses.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, ready/3]).
-hls_data(cell).
-hls_phases([ready]).
-hls_outputs([narrow, constant, small]).
-hls_tags([narrow, constant, small]).
-hls_mailbox_capacity(1).

%% A non-byte-aligned dynamic field is bounded by source-proven constants.
-record(narrow, {id = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:uN(25), flag = hls_type:zero() :: hls_nums:uN(1)}).
%% Omitted and exhaustive small domains exercise distinct codec cases.
-record(constant, {id = hls_type:zero() :: hls_nums:uN(3)}).
-record(small, {value = hls_type:zero() :: hls_nums:uN(5)}).
%% Both dynamic widths fit within one ordinary payload word.
-record(cell, {value = hls_type:zero() :: hls_nums:uN(25), small = hls_type:zero() :: hls_nums:uN(5)}).

-doc "Starts in the publishing phase with zero state.".
-spec init([]) -> {ok, ready, #cell{}}.
init([]) -> {ok, ready, #cell{}}.

-doc "Publishes constant-bounded and dynamic records; commands update state and are consumed.".
-spec ready(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #narrow{} | #constant{} | #small{}, #cell{}) -> hls_statem:cast_result(#cell{}).
ready(enter, _, C) -> {C, [{cast, narrow, #narrow{id = 5, value = C#cell.value, flag = 1}},
    {cast, constant, #constant{id = 6}}, {cast, small, #small{value = C#cell.small}}]};
ready(cast, #narrow{value = Value}, C) -> {ready, C#cell{value = Value}, consume};
ready(cast, #small{value = Value}, C) -> {ready, C#cell{small = Value}, consume};
ready(cast, #constant{}, C) -> {ready, C, consume}.
