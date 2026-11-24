-module(hls_topology_endpoint).
-moduledoc """
Endpoint and schema compatibility checks used by logical topology normalization. Resolves exact actors or bounded family members and compares process-free interface facts; physical routes and numeric selectors belong to backend planning.
""".
%% Logical endpoint and route compatibility checks.
-export([actor/3, validate_route/5, require_schemas/4]).

%% Exact declarations take precedence. Their namespace cannot overlap a valid
%% family member, but an unrelated tuple-shaped exact ID is still an actor ID.
-doc "Resolves an exact actor or bounded family member, raising the established actor diagnostics on failure.".
-spec actor(hls_logical_identity:id(), map(), term()) -> map().
actor(Id, #{actors := Actors, families := Families}, Context) ->
    case maps:find(Id, Actors) of
        {ok, Actor} -> Actor;
        error -> family_member(Id, Families, Context)
    end.

%% Resolves tuple-shaped IDs against a family while checking every coordinate bound.
-spec family_member(hls_logical_identity:id(), map(), term()) -> map().
family_member(Id, Families, Context) when is_tuple(Id), tuple_size(Id) > 1 ->
    [FamilyId | Coordinates] = tuple_to_list(Id),
    case maps:find(FamilyId, Families) of
        {ok, Family = #{shape := Shape}} when length(Coordinates) =:= length(Shape) ->
            case
                lists:all(
                    fun({Coordinate, Size}) ->
                        is_integer(Coordinate) andalso Coordinate >= 0 andalso Coordinate < Size
                    end,
                    lists:zip(Coordinates, Shape)
                )
            of
                true -> Family;
                false -> error({invalid_family_instance, Id, Shape})
            end;
        _ ->
            error({unknown_actor, Id, Context})
    end;
family_member(Id, _Families, Context) ->
    error({unknown_actor, Id, Context}).

-doc "Requires the destination to dispatch every emitted schema with exactly the source field layout.".
-spec validate_route(
    term(),
    term(),
    hls_process_interface:interface(),
    [atom()],
    hls_process_interface:interface()
) -> ok.
validate_route(Source, Recipient, SourceInterface, Emitted, DestinationInterface) ->
    Dispatched = hls_process_interface:dispatched_schemas(DestinationInterface),
    require_schemas(Source, Recipient, Emitted, Dispatched),
    lists:foreach(
        fun(Schema) ->
            #{fields := SourceFields} = hls_process_interface:schema(SourceInterface, Schema),
            #{fields := DestinationFields} = hls_process_interface:schema(
                DestinationInterface, Schema
            ),
            case SourceFields =:= DestinationFields of
                true ->
                    ok;
                false ->
                    error(
                        {incompatible_route_schema_layout, Source, Recipient, Schema, SourceFields,
                            DestinationFields}
                    )
            end
        end,
        Emitted
    ).

-doc "Requires `Dispatched` to contain every emitted schema or raises an incompatibility error.".
-spec require_schemas(term(), term(), [atom()], [atom()]) -> ok.
require_schemas(Source, Recipient, Emitted, Dispatched) ->
    case Emitted -- Dispatched of
        [] ->
            ok;
        Unsupported ->
            error({incompatible_route_schemas, Source, Recipient, Unsupported, Dispatched})
    end.
