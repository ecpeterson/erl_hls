-module(hls_topology_constants).
-moduledoc "Derives phase-local constants from exact actor routes and fixed startup messages.".
-export([specialize/2, specialize/3, requirements/2]).

-doc "Annotates opted-in exact-actor groups with compact state layouts; other groups retain ordinary storage.".
-spec specialize(hls_topology:plan(), [map()]) -> [map()].
specialize(Plan, Groups) -> specialize(Plan, Groups, hls_frame_layout:default()).

-doc "Annotates opted-in exact-actor groups using the selected ordinary-frame capacity for source validation.".
-spec specialize(hls_topology:plan(), [map()], hls_frame_layout:layout()) -> [map()].
specialize(Plan, Groups, Layout) ->
    case lists:any(fun(G) -> maps:get(specialize_state, G, false) end, Groups) of
        false -> Groups;
        true ->
            case {maps:get(families, Plan), maps:get(route_relations, Plan)} of
                {[], []} -> ok;
                _ -> error(state_specialization_requires_exact_topology)
            end,
            Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- maps:get(actors, Plan)], Layout),
            Selected = lists:usort([M || #{module := M, specialize_state := true} <- Groups]),
            Sources = maps:from_list([{M, source(M, maps:get(M, Interfaces), Layout)} || M <- Selected]),
            Facts = maps:from_list([{Id, actor(Plan, Id, maps:get(M, Sources), maps:get(M, Interfaces), Interfaces)} ||
                #{id := Id, module := M} <- maps:get(actors, Plan),
                lists:member(M, Selected)]),
            [group(G, Groups, Facts) || G <- Groups]
    end.

-doc "Adds complete module-scoped constant tables to actor generation requirements.".
-spec requirements([map()], map()) -> map().
requirements(Groups, Requirements) ->
    lists:foldl(fun
        (#{module := M, state_projection := P}, Acc) ->
            [Context] = proplists:get_value(hls_source_context, M:module_info(attributes)),
            Acc#{M := (maps:get(M, Acc))#{state_projection => P, source_options => Context}};
        (_, Acc) -> Acc
    end, Requirements, Groups).

%% Shared artifacts have one representation, so all groups of a module agree on fields.
-spec group(map(), [map()], map()) -> map().
group(G = #{module := M, state := #{fields := Fields, width := Width}}, Groups, Facts) ->
    Same = [{I, H} || {I, H = #{module := N}} <- lists:enumerate(0, Groups), M =:= N],
    case lists:all(fun({_, H}) -> maps:get(specialize_state, H, false) end, Same) of
        false -> G;
        true ->
            Rows = [{I, maps:get(base_slot, Member), maps:get(maps:get(id, Member), Facts)} ||
                {I, #{members := Members}} <- Same, Member <- Members],
            Keep = [Field || {Index, Field} <- lists:enumerate(2, Fields),
                lists:all(fun({_, _, #{states := States}}) ->
                    maps:size(States) > 0 andalso lists:all(fun(V) ->
                        case field_constant(V, Index) of
                            {ok, Value} -> exact_value(Value, maps:get(type, Field)) =/= unknown;
                            unknown -> false
                        end
                    end, maps:values(States))
                end, Rows)],
            Names = [maps:get(name, F) || F <- Keep],
            Removed = lists:sum([hls_type:width(maps:get(type, F)) || F <- Keep]),
            case Removed of
                0 -> G;
                _ -> G#{physical_data_width => Width - Removed,
                    state_projection => #{logical_width => Width, physical_width => Width - Removed,
                        fields => Fields, constants => Names,
                        rows => [row(I, Slot, Fact, Fields, Names) || {I, Slot, Fact} <- Rows]}}
            end
    end.

%% Packed field constants retain their type interpretation independently of the state codec.
-spec row(non_neg_integer(), non_neg_integer(), map(), [map()], [atom()]) -> map().
row(Instance, Slot, #{states := States, phases := Phases, source_hash := Hash,
        schemas := Schemas, startup := Startup}, Fields, Names) ->
    #{instance => Instance, slot => Slot, source_hash => Hash, admissible_schemas => Schemas,
      startup_hash => binary:encode_hex(crypto:hash(sha256, term_to_binary(Startup))),
      phases => [#{phase => Phase, values => [begin
          {ok, Value} = field_constant(maps:get(Phase, States), Index),
          Type = maps:get(type, F), Bits = hls_type:pack_exact(Value, Type),
          Size = bit_size(Bits), <<Integer:Size>> = Bits,
          #{name => maps:get(name, F), width => Size, value => Integer}
      end || {Index, F} <- lists:enumerate(2, Fields), lists:member(maps:get(name, F), Names)]}
      || Phase <- Phases, maps:is_key(Phase, States)]}.

%% A missing tuple shape never establishes an invariant field.
-spec field_constant(hls_actor_constants:value(), pos_integer()) -> {ok, term()} | unknown.
field_constant({tuple, Values}, Index) when Index =< length(Values) ->
    hls_actor_constants:constant(lists:nth(Index, Values));
field_constant(_, _) -> unknown.

%% Source validation is shared across instances, only within this planning pass.
-spec source(module(), map(), hls_frame_layout:layout()) -> map().
source(Module, Interface, Layout) ->
    case maps:get(reply_storage_width, Interface, 0) of
        0 -> ok;
        _ -> error({state_specialization_protocol, Module})
    end,
    [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
    Source = maps:get(source_name, Context), Forms = hls_records:resolve(hls_source:read(Source, Context)),
    %% Validate ordinary lowering, then inspect its current source without executing callbacks.
    _ = xls_parse:actor_artifact(Source, Context, Layout),
    #{forms => Forms, phases => maps:get(phases, Interface),
      source_hash => binary:encode_hex(crypto:hash(sha256, term_to_binary(Forms)))}.

%% Startup payloads are exact; ordinary producers contribute only their conservative schema union.
-spec actor(map(), term(), map(), map(), map()) -> map().
actor(Plan, Id, Source = #{forms := Forms, phases := Phases}, Interface, Interfaces) ->
    Startup = lists:append([Ms || #{target := Target, messages := Ms} <- maps:get(startup, Plan), Target =:= Id]),
    ActorModules = maps:from_list([{A, M} || #{id := A, module := M} <- maps:get(actors, Plan)]),
    Incoming = lists:usort(lists:append([source_schemas(SourceId, Port, ActorModules, Interfaces, Interface) ||
        #{source := {SourceId, Port}, recipients := Recipients} <- maps:get(routes, Plan),
        lists:member({actor, Id}, Recipients)])),
    %% External frames are not trusted merely because ingress has declared schemas.
    Open = lists:any(fun(#{targets := Targets}) ->
        lists:any(fun(#{recipients := Recipients}) ->
            lists:any(fun(R) -> maps:get(actor, R, none) =:= Id end, Recipients)
        end, Targets)
    end, maps:get(ingresses, Plan, [])),
    Schemas = case Open of true -> [maps:get(name, S) || S <- maps:get(schemas, Interface)]; false -> Incoming end,
    Messages = [message(M, Interface) || M <- Startup] ++
        [hls_actor_constants:unknown_record(N, length(maps:get(fields, hls_actor_interface:schema(Interface, N)))) || N <- Schemas],
    (maps:without([forms], Source))#{states => hls_actor_constants:from_source(Forms, Phases, Messages),
        schemas => Schemas, startup => Startup}.

%% Typed internal actors establish their emitted schema set; unknown producers establish nothing.
-spec source_schemas(term(), atom(), map(), map(), map()) -> [atom()].
source_schemas(Id, Port, Actors, Interfaces, Interface) ->
    case maps:find(Id, Actors) of
        {ok, Module} -> hls_actor_interface:output_schemas(maps:get(Module, Interfaces), Port);
        error -> [maps:get(name, S) || S <- maps:get(schemas, Interface)]
    end.

%% Packing may round a legal host value; lose that fact without rejecting the topology.
-spec message(tuple(), map()) -> hls_actor_constants:value().
message(Message, Interface) ->
    Name = element(1, Message),
    #{fields := Fields} = hls_actor_interface:schema(Interface, Name),
    {tuple, [hls_actor_constants:value(Name) | [exact_value(Value, Type) ||
        {Value, #{type := Type}} <- lists:zip(tl(tuple_to_list(Message)), Fields)]]}.

%% Reject invalid values normally, but retain storage when a legal codec normalizes a value.
-spec exact_value(term(), hls_type:descriptor()) -> hls_actor_constants:value().
exact_value(Value, Type) ->
    try hls_type:pack_exact(Value, Type) of
        _ -> hls_actor_constants:value(Value)
    catch error:{inexact_packing, Type} -> unknown end.
