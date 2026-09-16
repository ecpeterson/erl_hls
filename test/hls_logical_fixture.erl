-module(hls_logical_fixture).
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(state).
-hls_tags([step, read, result, bundle, reset]).
-hls_replies([{step, [result]}, {read, [result]}, {bundle, [bundle]}]).

-record(state, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:sN(9)
}).
-record(step, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    delta = hls_type:zero() :: hls_nums:sN(9)
}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(result, {
    enabled = hls_type:zero() :: hls_bool:bool(),
    count = hls_type:zero() :: hls_nums:uN(3),
    value = hls_type:zero() :: hls_nums:sN(9)
}).
-record(bundle, {
    flags = hls_type:zero() :: hls_vec:vector(hls_bool:bool(), 4),
    values = hls_type:zero() :: hls_vec:vector(hls_vec:vector(hls_nums:sN(5), 2), 4)
}).
-record(reset, {unused = hls_type:zero() :: hls_nums:u32()}).

init([]) -> #state{enabled = true, count = 5, value = -129}.

handle_call(#step{enabled = Enabled, count = Count, delta = Delta}, State) when Enabled ->
    Next = State#state{enabled = not State#state.enabled,
        count = hls_nums:wrap(hls_nums:uN(3), State#state.count + Count),
        value = add(State#state.value, Delta)},
    {reply, result(Next), Next};
handle_call(#step{}, State) -> {reply, result(State), State};
handle_call(#read{}, State) when State#state.enabled ->
    {reply, result(State), State};
handle_call(#read{}, State) -> {reply, result(State), State};
handle_call(Bundle = #bundle{flags = Flags, values = Values}, State) ->
    Pair = hls_vec:nth(2, Values),
    Squared = hls_vec:dot(hls_nums:sN(11), Pair, Pair),
    Updated = hls_vec:set(1, Pair, hls_nums:wrap(hls_nums:sN(5), Squared)),
    Reply = Bundle#bundle{flags = hls_vec:set(2, Flags, not hls_vec:nth(2, Flags)),
        values = hls_vec:set(2, Values, Updated)},
    {reply, Reply, State}.

handle_cast(#reset{}, _State) -> {noreply, #state{}}.

-spec add(hls_nums:sN(9), hls_nums:sN(9)) -> hls_nums:sN(9).
add(Left, Right) -> hls_nums:wrap(hls_nums:sN(9), Left + Right).

-spec result(#state{}) -> #result{}.
result(#state{enabled = Enabled, count = Count, value = Value}) ->
    #result{enabled = Enabled, count = Count, value = Value}.
