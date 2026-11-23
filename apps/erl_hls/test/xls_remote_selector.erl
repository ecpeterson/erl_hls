-module(xls_remote_selector).
-moduledoc "Ordinary source helper used to check XLS optimization across generated module boundaries.".
%% Public value helper; both arguments remain eager Erlang computations.
-export([choose/3]).

-doc "Selects the left or right value according to the Boolean input.".
-spec choose(boolean(), hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
choose(KeepLeft, Left, Right) ->
    case KeepLeft of
        true -> Left;
        false -> Right
    end.
