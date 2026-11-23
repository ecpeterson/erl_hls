-module(enum_collection_math).
-moduledoc false.
-export([fault/1]).
%% These private aliases must resolve in this module, not in its caller.
-type mode() :: idle | busy | done.
%% Output codebook puts busy at code two.
-type fault() :: none | actor | busy.
-doc "Maps a mode to an independently encoded fault domain; busy has a different code in each.".
-spec fault(mode()) -> fault().
fault(busy) -> busy;
fault(_) -> none.
