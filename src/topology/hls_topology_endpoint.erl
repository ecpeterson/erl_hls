-module(hls_topology_endpoint).
-moduledoc false.
-export([actor/3, validate_route/5, require_schemas/4]).

%% Exact declarations take precedence. Their namespace cannot overlap a valid
%% family member, but an unrelated tuple-shaped exact ID is still an actor ID.
actor(Id, #{actors := Actors, families := Families}, Context) ->
    case maps:find(Id, Actors) of
        {ok, Actor} -> Actor;
        error -> family_member(Id, Families, Context)
    end.

family_member(Id, Families, Context) when is_tuple(Id), tuple_size(Id) > 1 ->
    [FamilyId | Coordinates] = tuple_to_list(Id),
    case maps:find(FamilyId, Families) of
        {ok, Family = #{shape := Shape}} when length(Coordinates) =:= length(Shape) ->
            case lists:all(fun({Coordinate, Size}) ->
                is_integer(Coordinate) andalso Coordinate >= 0 andalso Coordinate < Size
            end, lists:zip(Coordinates, Shape)) of
                true -> Family;
                false -> error({invalid_family_instance, Id, Shape})
            end;
        _ -> error({unknown_actor, Id, Context})
    end;
family_member(Id, _Families, Context) ->
    error({unknown_actor, Id, Context}).

validate_route(Source, Recipient, SourceInterface, Emitted, DestinationInterface) ->
    Dispatched = hls_actor_interface:dispatched_schemas(DestinationInterface),
    require_schemas(Source, Recipient, Emitted, Dispatched),
    lists:foreach(fun(Schema) ->
        #{fields := SourceFields} = hls_actor_interface:schema(SourceInterface, Schema),
        #{fields := DestinationFields} = hls_actor_interface:schema(DestinationInterface, Schema),
        case SourceFields =:= DestinationFields of
            true -> ok;
            false -> error({incompatible_route_schema_layout,
                Source, Recipient, Schema, SourceFields, DestinationFields})
        end
    end, Emitted).

require_schemas(Source, Recipient, Emitted, Dispatched) ->
    case Emitted -- Dispatched of
        [] -> ok;
        Unsupported -> error({incompatible_route_schemas,
            Source, Recipient, Unsupported, Dispatched})
    end.
