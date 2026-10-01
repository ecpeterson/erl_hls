%%%% Checked boundary encoding shared by compact and instance topologies.
-module(xls_topology_ingress).
-moduledoc false.
-export([lower/2, condition/3, target_enum/1]).
-define(U16_EXTENT, 16#10000).

lower([], _Endpoints) -> [];
lower([Ingress = #{
    id := Id,
    kind := rectangle,
    shape := [Width, Height],
    targets := Targets
}], Endpoints) when Width =< ?U16_EXTENT, Height =< ?U16_EXTENT ->
    length(Targets) =< 4 orelse error({ingress_targets, length(Targets)}),
    AnnotatedTargets = [
        annotate_ingress_target(Index, Target, Endpoints)
        || {Index, Target} <- lists:enumerate(0, Targets)
    ],
    Recipients = ingress_recipients(AnnotatedTargets),
    [Ingress#{
        index => 0,
        input_name => [xls_topology_profile:identifier(Id, ingress_id), "_in"],
        targets => AnnotatedTargets,
        recipients => Recipients
    }];
lower([#{shape := Shape}], _Endpoints) ->
    error({ingress_shape, Shape, ?U16_EXTENT});
lower(Ingresses, _Endpoints) ->
    error({ingress_count, length(Ingresses)}).

annotate_ingress_target(
    Index,
    Target = #{id := Id, schemas := Schemas, recipients := Recipients},
    Endpoints
) ->
    TargetName = string:uppercase(
        xls_topology_profile:identifier(Id, ingress_target)),
    Encodings = lists:usort([
        begin
            Interface = interface(Recipient, Endpoints),
            #{selector := Selector, fields := Fields} =
                hls_actor_interface:schema(Interface, Schema),
            {Schema, Selector, Fields}
        end
        || Schema <- Schemas,
           Recipient <- Recipients
    ]),
    lists:foreach(
        fun(Schema) ->
            case [Encoding || Encoding = {Name, _, _} <- Encodings,
                    Name =:= Schema] of
                [_] -> ok;
                Values -> error({ingress_encoding, Id, Schema, Values})
            end
        end,
        Schemas
    ),
    Target#{
        selector => Index,
        target_name => TargetName,
        encodings => Encodings
    }.

ingress_recipients(Targets) ->
    ByEndpoint = lists:foldl(fun(#{id := TargetId, recipients := Recipients}, Acc) ->
        lists:foldl(fun(Recipient, Inner) ->
            Key = endpoint(Recipient),
            maps:update_with(Key, fun(Existing = #{targets := Ids}) ->
                Existing#{targets := [TargetId | Ids]}
            end, Recipient#{targets => [TargetId]}, Inner)
        end, Acc, Recipients)
    end, #{}, Targets),
    [Recipient#{targets := lists:sort(Ids)} || {_Key, Recipient = #{targets := Ids}}
        <- lists:sort(maps:to_list(ByEndpoint))].

endpoint(#{family := Id}) -> {family, Id};
endpoint(#{actor := Id}) -> {actor, Id}.

interface(#{family := Id}, #{families := Families}) ->
    #{interface := Interface} = maps:get(Id, Families), Interface;
interface(#{actor := Id}, #{actors := Actors}) ->
    #{interface := Interface} = maps:get(Id, Actors), Interface.

%% A target has one wire encoding across all its destinations. Compute the
%% accepted envelope from those schemas rather than maintaining a second ABI.
condition(TargetIds, #{targets := Targets}, Packet) ->
    lists:join(" || ", [["(", Packet, ".target == u2:", integer_to_list(Selector),
        " && (", lists:join(" || ", [encoding_condition(Encoding, Packet)
            || Encoding <- Encodings]), "))"] ||
        #{id := Id, selector := Selector, encodings := Encodings} <- Targets,
        lists:member(Id, TargetIds)]).

encoding_condition({_Schema, Selector, Fields}, Packet) ->
    Bits = lists:sum([hls_type:width(Type) || #{type := Type} <- Fields]),
    Words = (Bits + 31) div 32,
    ["(", Packet, ".frame.header.op == u8:", integer_to_list(Selector),
        " && ", Packet, ".frame.header.payload_words == u8:", integer_to_list(Words), ")"].

target_enum(#{targets := Targets}) ->
    [
        "pub enum ControlTarget : u2 {\n",
        [["  ", maps:get(target_name, Target), " = ",
            integer_to_list(maps:get(selector, Target)), ",\n"]
            || Target <- Targets],
        "}\n\n"
    ].

