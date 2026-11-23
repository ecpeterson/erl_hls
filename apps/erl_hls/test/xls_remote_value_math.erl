-module(xls_remote_value_math).
-moduledoc "Ordinary pure source module, with no provider callback or parse transform.".
%% Public numerical operations for the remote-helper witness.
-export([calculate/1, nonzero/1, first/2, pair/1]).
-doc "Combines a private helper with a same-named helper in another module.".
-spec calculate(hls_nums:u32()) -> hls_nums:u32().
calculate(Value) -> offset(Value) + xls_remote_value_bias:offset(Value).
%% Qualified self calls use an exported function, as required by ordinary BEAM.
-spec offset(hls_nums:u32()) -> hls_nums:u32().
offset(Value) -> ?MODULE:nonzero(increment(Value)).
%% Private closure members require no export.
-spec increment(hls_nums:u32()) -> hls_nums:u32().
increment(Value) -> Value + 1.
-doc "Returns a nonzero input, otherwise raises a selected assignment failure.".
-spec nonzero(hls_nums:u32()) -> hls_nums:u32().
nonzero(Value) -> true = Value =/= 0, Value.
-doc "Returns its first argument after both arguments have been evaluated.".
-spec first(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
first(Value, _) -> Value.
-doc "Preserves a flag and transforms the scalar component through a remote helper.".
-spec pair({boolean(), hls_nums:u32()}) -> {boolean(), hls_nums:u32()}.
pair({Flag, Value}) -> {Flag, xls_remote_value_bias:offset(Value)}.
