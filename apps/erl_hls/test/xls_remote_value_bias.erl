-module(xls_remote_value_bias).
-moduledoc "Second source namespace in the finite cross-module witness.".
%% Public helper, deliberately sharing another module's private function spelling.
-export([offset/1]).
-doc "Adds a fixed offset; the finite witness keeps the result within u32.".
-spec offset(hls_nums:u32()) -> hls_nums:u32().
offset(Value) -> Value + 3.
