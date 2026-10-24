-module(xls_statem_gather_layout).
-moduledoc "Authoritative numeric layout of packed gather progress, independent of payload storage, observation policy and target-language syntax.".
-export([progress/1]).
-export_type([field_name/0, field/0, layout/0]).

-doc "Semantic fields shared by ordinary gather codecs and passive observers.".
-type field_name() :: status | site | key | remaining | expected | seen | failure.

-doc "A positive-width slice, addressed from the least-significant packed bit.".
-type field() :: #{offset := non_neg_integer(), width := pos_integer()}.

-doc "The maximum site capacity, total progress width and named slices; absent gathers have zero capacity/width and no fields.".
-type layout() :: #{capacity := non_neg_integer(), width := non_neg_integer(),
    fields := #{field_name() => field()}}.

-doc "Derives the existing packed progress ABI from a checked structural or lowered gather descriptor. Membership masks cover the largest site regardless of site order. Element values and source validation are separate; none has no stored progress.".
-spec progress(none | map()) -> layout().
progress(none) -> #{capacity => 0, width => 0, fields => #{}};
progress(#{sites := [_ | _] = Sites}) ->
    Capacity = lists:max([maps:get(size, maps:get(population, Site)) || Site <- Sites]),
    Sizes = [{status, 2}, {site, 8}, {key, 32}, {remaining, 8},
        {expected, Capacity}, {seen, Capacity}, {failure, 16}],
    {Width, Fields} = lists:foldl(fun({Name, Bits}, {Offset, Acc}) ->
        {Offset + Bits, Acc#{Name => #{offset => Offset, width => Bits}}}
    end, {0, #{}}, Sizes),
    #{capacity => Capacity, width => Width, fields => Fields}.
