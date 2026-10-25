-module(hls_protocol_arithmetic).
-moduledoc "Binds disjoint scalar-completion groups to freshly compiled native actors. No source facts or prebuilt kernels are accepted.".
-export([plan/3, receiver/3]).

-doc "Resolves groups of two or three logical actor IDs against a fresh bundle and its native placement. Every member must use the same source module with scalar reductions, no indexed gathers or retained calls. Groups must be disjoint and wholly native. Returns source-bound indices and cursor costs; this is sharing configuration, not progress, resource-fit or timing admission.".
-spec plan([[term()]], map(), [non_neg_integer()]) -> [map()].
plan(Groups, #{topology := #{actors := Actors}, modules := Modules}, Native) when is_list(Groups) ->
    Plans = [group(I, Ids, Actors, Modules, Native) || {I, Ids} <- lists:enumerate(0, Groups)],
    Members = lists:append([Is || #{members := Is} <- Plans]),
    case length(Members) =:= length(lists:usort(Members)) of
        true -> Plans;
        false -> error(overlapping_arithmetic_groups)
    end;
plan(Other, _, _) -> error({invalid_arithmetic_groups, Other}).

%% Bind identity and source compatibility before emitting any hardware.
-spec group(non_neg_integer(), term(), [map()], map(), [non_neg_integer()]) -> map().
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

-doc "Selects the shared-owner template only for a checked group's receiver. Reuses the fresh source spec and ordinary compiler execution; ungrouped artifacts are unchanged. Call only after plan/3 on this same bundle, before attaching an inbox.".
-spec receiver(non_neg_integer(), [map()], hls_local_actor:artifact()) -> hls_local_actor:artifact().
receiver(Index, Groups, Artifact = #{program := Program}) ->
    Spec = xls_actor_program:spec(Program),
    case [G || #{index := G, members := Members} <- Groups, lists:member(Index, Members)] of
        [] -> Artifact;
        [Group] -> Artifact#{completion => #{mode => shared, group => Group},
            dslx := iolist_to_binary([xls_shared_codegen:execution(Spec), hls_local_protocol:ports(Spec, shared)])}
    end.
