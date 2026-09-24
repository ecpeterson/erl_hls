-module(xls_comparison_fixture).
-moduledoc "Mixed-width comparisons through guards, helpers, branches and framed replies.".
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).
-hls_data(data).
-hls_tags([clear, request, '_Value_1']).
-hls_replies([{request, ['_Value_1']}]).
-record(data, {value = hls_type:zero() :: hls_nums:u8()}).
-record(clear, {value = hls_type:zero() :: hls_nums:u8()}).
-record(request, {left = hls_type:zero() :: hls_nums:s8(), right = hls_type:zero() :: hls_nums:uN(9)}).
-record('_Value_1', {less = hls_type:zero() :: hls_bool:bool(),
    equal = hls_type:zero() :: hls_bool:bool(), bounded = hls_type:zero() :: hls_bool:bool(),
    helper = hls_type:zero() :: hls_bool:bool()}).

-doc "Initializes an idle comparison service.".
-spec init([]) -> #data{}.
init([]) -> #data{}.

-doc "Returns integer comparisons while preserving the source record named Value_1.".
-spec handle_call(#request{}, #data{}) -> {reply, #'_Value_1'{}, #data{}}.
handle_call(#request{left = Value, right = Other}, Data) ->
    Bounded = if Value < 128, Other < 512 -> true; true -> false end,
    Equal = case Value >= Other of true -> Value =:= Other; false -> false end,
    {reply, report(Value < Other, Equal, Bounded, less(Value, Other)), Data}.

%% A plain helper binding used to shadow the struct type in its own body.
-spec report(boolean(), boolean(), boolean(), boolean()) -> #'_Value_1'{}.
report(Value, Equal, Bounded, Helper) ->
    #'_Value_1'{less = Value, equal = Equal, bounded = Bounded, helper = Helper}.

%% Separate concrete signatures prove the helper's mixed integer argument types.
-spec less(hls_nums:s8(), hls_nums:uN(9)) -> boolean().
less(A, B) -> A < B.

-doc "Leaves the comparison service unchanged.".
-spec handle_cast(#clear{}, #data{}) -> {noreply, #data{}}.
handle_cast(#clear{}, Data) -> {noreply, Data}.
