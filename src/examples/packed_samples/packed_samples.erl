-module(packed_samples).
-moduledoc """
A packed-sample accumulator. Each 24-bit input contains a 3-bit format tag
(5), five flag bits and a signed 16-bit little-endian delta. A receipt returns
those flags with the low 16 bits of the running sum, plus its full sum and a
modulo-32 sample count. Invalid format tags fail at decode/1.
""".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(state).
-hls_tags([sample, read, receipt, clear]).
-hls_replies([{sample, [receipt]}, {read, [receipt]}]).

-record(state, {
    last = hls_type:zero() :: hls_bits:bits(24),
    count = hls_type:zero() :: hls_nums:uN(5),
    total = hls_type:zero() :: hls_nums:s32()
}).
-record(sample, {word = hls_type:zero() :: hls_bits:bits(24)}).
-record(clear, {unused = hls_type:zero() :: hls_nums:uN(1)}).
-record(read, {unused = hls_type:zero() :: hls_nums:uN(1)}).
-record(receipt, {
    word = hls_type:zero() :: hls_bits:bits(24),
    count = hls_type:zero() :: hls_nums:uN(5),
    total = hls_type:zero() :: hls_nums:s32()
}).

init([]) -> #state{last = <<5:3, 0:5, 0:16/little>>}.

handle_call(#sample{word = Word}, State = #state{count = Count, total = Total}) ->
    {Flags, Delta} = decode(Word),
    Sum = hls_nums:wrap(hls_nums:s32(), Total + hls_type:as(hls_nums:s32(), Delta)),
    Next = State#state{last = <<5:3, Flags:5, Sum:16/signed-little>>,
        count = hls_nums:wrap(hls_nums:uN(5), Count + 1), total = Sum},
    {reply, receipt(Next), Next};
handle_call(#read{}, State) -> {reply, receipt(State), State}.

handle_cast(#clear{}, _State) -> {noreply, #state{last = <<5:3, 0:5, 0:16/little>>}}.

-spec decode(hls_bits:bits(24)) -> {hls_nums:uN(5), hls_nums:s16()}.
decode(<<5:3, Flags:5, Delta:16/signed-little>>) -> {Flags, Delta}.

-spec receipt(#state{}) -> #receipt{}.
receipt(#state{last = Word, count = Count, total = Total}) ->
    #receipt{word = Word, count = Count, total = Total}.
