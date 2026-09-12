-module(xls_init_gs_fixture).
-behavior(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).

-hls_data(ledger).
-hls_tags([query, change, report]).

-record(query, {value = hls_type:zero() :: hls_nums:u32()}).
-record(change, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {
    value = hls_type:zero() :: hls_nums:u32(),
    default = hls_type:zero() :: hls_nums:u32()
}).
-record(ledger, {
    value = hls_type:zero() :: hls_nums:u32(),
    default = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    Base = initial_value(),
    Expected = hls_nums:wrap(hls_nums:u32(), 41),
    Expected = Base,
    Value = case Base of
        41 -> Base + 1;
        _ ->
            Other = hls_nums:wrap(hls_nums:u32(), 0),
            Other = Base,
            Base
    end,
    #ledger{value = Value}.

handle_call(#query{}, State) ->
    {reply, #report{value = State#ledger.value, default = State#ledger.default}, State}.

handle_cast(#change{value = Value}, State) ->
    {noreply, State#ledger{value = Value}}.

-spec initial_value() -> hls_nums:u32().
initial_value() -> hls_nums:wrap(hls_nums:u32(), 41).
