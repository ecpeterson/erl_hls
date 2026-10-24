-module(xls_statem_gather_layout).
-moduledoc "Typed packed gather progress shared by ordinary codecs and passive observers; payload storage and observation policy remain separate.".
-export([progress/1, codec/1]).
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
progress(G = #{sites := [_ | _]}) ->
    #{width := Width, fields := Fields} = codec(G),
    #{capacity => capacity(G), width => Width,
        fields => maps:from_list([{Name, #{offset => Prefix, width => Bits}}
            || #{name := Name, prefix := Prefix, width := Bits} <- Fields])}.

-doc "Defines progress field types and their low-bit-first encoding. Generated gather enums and aliases, plus hls_failure, must be in scope when rendering codecs; none has an empty layout.".
-spec codec(none | map()) -> xls_struct_codec:layout().
codec(none) -> xls_struct_codec:layout([], lsb);
codec(G) ->
    Members = xls_named_bits:local('GatherMembers', capacity(G)),
    xls_struct_codec:layout([
        {status, xls_named_bits:local('GatherStatus', 2)},
        {site, xls_named_bits:local('GatherSite', 8)},
        {key, hls_nums:u32()},
        {remaining, hls_nums:u8()},
        {expected, Members},
        {seen, Members},
        {failure, xls_named_bits:qualified(hls_failure, 'Code', 16)}
    ], lsb).

%% Membership masks cover the largest checked site, independent of source order.
-spec capacity(map()) -> pos_integer().
capacity(#{sites := [_ | _] = Sites}) ->
    lists:max([maps:get(size, maps:get(population, Site)) || Site <- Sites]).
