-module(hls_protocol_arithmetic).
-moduledoc "Binds disjoint scalar-completion groups to freshly compiled native actors. No source facts or prebuilt kernels are accepted.".
-export([plan/3, select/3]).
-export_type([group/0]).

-doc "One disjoint group of two or three compatible native scalar completions, identified by whole-topology actor indices.".
-type group() :: #{index := non_neg_integer(), members := [non_neg_integer(), ...],
    module := module(), cursor_bits := 1 | 2}.

-doc "Resolves groups of two or three logical actor IDs against a fresh bundle and its native placement. Every member must use the same source module with scalar reductions, no indexed gathers or retained calls. Groups must be disjoint and wholly native. Returns source-bound indices and cursor costs; this is sharing configuration, not progress, resource-fit or timing admission.".
-spec plan([[term()]], map(), [non_neg_integer()]) -> [group()].
plan(Groups, #{topology := #{actors := Actors}, modules := Modules}, Native) when is_list(Groups) ->
    Plans = [group(I, Ids, Actors, Modules, Native) || {I, Ids} <- lists:enumerate(0, Groups)],
    Members = lists:append([Is || #{members := Is} <- Plans]),
    case length(Members) =:= length(lists:usort(Members)) of
        true -> Plans;
        false -> error(overlapping_arithmetic_groups)
    end;
plan(Other, _, _) -> error({invalid_arithmetic_groups, Other}).

%% Bind identity and source compatibility before emitting any hardware.
-spec group(non_neg_integer(), term(), [map()], map(), [non_neg_integer()]) -> group().
group(I, Ids, Actors, Modules, Native) when is_list(Ids), length(Ids) >= 2, length(Ids) =< 3 ->
    Bindings = [member(Id, Actors, Native) || Id <- Ids],
    case lists:usort([M || {_, M} <- Bindings]) of
        [Module] ->
            #{program := Program} = maps:get(Module, Modules),
            Spec = xls_actor_program:spec(Program),
            case Spec of
                #{reductions := R, gathers := none, retained_calls := none} when R =/= none -> ok;
                _ -> error({unsupported_shared_completion, Module})
            end,
            #{index => I, members => [N || {N, _} <- Bindings], module => Module,
              cursor_bits => case length(Ids) of 2 -> 1; 3 -> 2 end};
        _ -> error({incompatible_arithmetic_group, Ids})
    end;
group(_, Ids, _, _, _) -> error({arithmetic_group_size, Ids}).

%% Global indices remain stable across partitioned roles; a group cannot cross a role boundary.
-spec member(term(), [map()], [non_neg_integer()]) -> {non_neg_integer(), module()}.
member(Id, Actors, Native) ->
    case [{I, M} || {I, #{id := Name, module := M}} <- lists:enumerate(0, Actors), Name =:= Id, lists:member(I, Native)] of
        [Binding] -> Binding;
        _ -> error({arithmetic_member_not_native, Id})
    end.

-doc "Selects completion ownership from groups checked against this same source bundle. It changes only the static completion descriptor; no hardware is rendered and ungrouped sources are unchanged.".
-spec select(non_neg_integer(), [group()], Source) -> Source
    when Source :: hls_local_actor:source() | hls_local_actor:artifact().
select(Index, Groups, Source) ->
    case [G || #{index := G, members := Members} <- Groups, lists:member(Index, Members)] of
        [] -> Source;
        [Group] -> Source#{completion => #{mode => shared, group => Group}}
    end.
