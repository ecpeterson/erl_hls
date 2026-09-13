-module(hls_float_fixture).
-behavior(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2, compute/3]).

-ifndef(FLOAT_TYPE).
-define(FLOAT_TYPE, float32).
-endif.
-ifdef(HALF).
-define(PAD, , padding = hls_type:zero() :: hls_nums:u16()).
-else.
-define(PAD, ).
-endif.

-hls_data(ledger).
-hls_tags([calculate, read, load, report]).
-record(ledger, {
    value = hls_type:zero() :: hls_nums:?FLOAT_TYPE(),
    history = hls_type:zero() :: hls_vec:vector(hls_vec:vector(hls_nums:?FLOAT_TYPE(), 2), 2)
}).
-record(calculate, {mode = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:?FLOAT_TYPE() ?PAD}).
-record(load, {value = hls_type:zero() :: hls_nums:?FLOAT_TYPE() ?PAD}).
-record(read, {unused = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:?FLOAT_TYPE() ?PAD}).

init([]) -> #ledger{value = hls_float:literal(hls_nums:?FLOAT_TYPE(), 1.5)}.

handle_call(#calculate{mode = Mode, value = Y}, State) ->
    Value = compute(Mode, State#ledger.value, Y),
    Row = hls_vec:nth(1, State#ledger.history),
    History = hls_vec:set(1, State#ledger.history, hls_vec:set(2, Row, Value)),
    {reply, #report{value = Value}, State#ledger{value = Value, history = History}};
handle_call(#read{}, State) ->
    {reply, #report{value = State#ledger.value}, State}.

handle_cast(#load{value = Value}, State) ->
    {noreply, State#ledger{value = Value}}.

-spec compute(hls_nums:u32(), hls_nums:?FLOAT_TYPE(), hls_nums:?FLOAT_TYPE()) -> hls_nums:?FLOAT_TYPE().
compute(Mode, X, Y) ->
    case Mode of
        0 -> hls_float:add(hls_nums:?FLOAT_TYPE(), X, Y);
        1 -> hls_float:sub(hls_nums:?FLOAT_TYPE(), X, Y);
        2 -> hls_float:mul(hls_nums:?FLOAT_TYPE(), X, Y);
        3 -> case hls_float:eq(hls_nums:?FLOAT_TYPE(), X, Y) of
            true -> hls_float:literal(hls_nums:?FLOAT_TYPE(), 1.0);
            false -> hls_float:literal(hls_nums:?FLOAT_TYPE(), 0.0)
        end;
        4 -> case hls_float:lt(hls_nums:?FLOAT_TYPE(), X, Y) of
            true -> hls_float:literal(hls_nums:?FLOAT_TYPE(), 1.0);
            false -> hls_float:literal(hls_nums:?FLOAT_TYPE(), 0.0)
        end;
        5 -> Y;
        6 -> case hls_float:eq(hls_nums:?FLOAT_TYPE(), X, Y) of
            true -> X;
            false -> hls_float:mul(hls_nums:?FLOAT_TYPE(), X, Y)
        end
    end.
