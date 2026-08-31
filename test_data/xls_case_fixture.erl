%%%% xls_case_fixture
%%%%
%%%% Compile-only conformance fixture for expression-level case patterns in
%%%% both the generic expression lowerer and hls_gs callback renderer.

-module(xls_case_fixture).

-hls_data(state).
-hls_tags([query, update, reply]).

-record(query, {
    mode = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(update, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(reply, {
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(state, {
    fallback = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    #state{}.

handle_call(
    Request = #query{mode = Mode, value = Value},
    State
) ->
    Selected = case {Mode, Value} of
        {0, Choice} -> Choice;
        {1, Choice} when Choice < 8 -> Choice + 1;
        _ -> State#state.fallback
    end,
    Reply = case Request of
        Whole = #query{mode = 0} ->
            #reply{value = Whole#query.value};
        #query{value = Original} when Original < 8 ->
            #reply{value = Selected};
        _ ->
            #reply{value = State#state.fallback}
    end,
    {reply, Reply, State}.

handle_cast(#update{value = Value}, State) ->
    {noreply, State#state{fallback = Value}}.
