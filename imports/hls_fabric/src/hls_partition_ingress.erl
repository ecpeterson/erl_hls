-module(hls_partition_ingress).
-moduledoc "Rectangle control over checked device ownership; delivery is ordered per actor, not atomic across devices.".
-export([lower/3, commands/5, select/5]).

-doc "Checks shared ingress encodings and expands logical selections to placed actor points.".
-spec lower(hls_topology:plan(), [map()], map()) -> [map()].
lower(#{ingresses := Ingresses, actors := Exact, families := Families}, Actors, Interfaces) ->
    Endpoints = maps:from_list([{Kind, maps:from_list([{Id,
        A#{interface => maps:get(Module, Interfaces)}} || A = #{id := Id, module := Module} <- Entries])}
        || {Kind, Entries} <- [{actors, Exact}, {families, Families}]]),
    [Ingress#{bindings => lists:append([bindings(R, Actors)
        || R <- maps:get(recipients, Ingress)])}
        || Ingress <- xls_topology_ingress:lower(Ingresses, Endpoints)].

%% Preserve global embedded coordinates; placement changes only delivery ownership.
-spec bindings(map(), [map()]) -> [map()].
bindings(#{family := Family, scale := [SX, SY], offset := [OX, OY], targets := Targets}, Actors) ->
    [A#{point => [OX + SX*X, OY + SY*Y], targets => Targets}
        || A = #{identity := {family, Id, [X, Y]}} <- Actors, Id =:= Family];
bindings(#{actor := Actor, at := Point, targets := Targets}, Actors) ->
    [A#{point => Point, targets => Targets}
        || A = #{identity := {actor, Id}} <- Actors, Id =:= Actor].

-doc "Packs one spatial command per selected device, retaining global bounds. Raises on invalid bounds, targets or schemas; the caller must preserve order and abort partial failure without replay.".
-spec commands(map(), atom(), atom(), {integer(), integer(), integer(), integer()}, tuple()) ->
    [{term(), bitstring()}].
commands(Partition, Id, TargetId, Rectangle, Message) ->
    #{packet := Packet, recipients := Recipients} =
        select(Partition, Id, TargetId, Rectangle, Message),
    [{Device, Packet} || Device <- lists:usort([D || #{device := D} <- Recipients])].

-doc "Validates and packs one rectangle, returning its exact selected actor bindings with the common spatial frame. Selection may be empty; each consumer decides whether that is admissible. Preserves checked binding order and metadata so host and native recipients share one geometry decision. Raises on invalid bounds, target or record encoding before any delivery.".
-spec select(map(), atom(), atom(), {integer(), integer(), integer(), integer()}, tuple()) ->
    #{packet := bitstring(), recipients := [map()]}.
select(#{ingresses := Ingresses}, Id, TargetId, Rectangle, Message) ->
    [#{shape := Shape, targets := Targets, bindings := Bindings}] =
        [I || I = #{id := Name} <- Ingresses, Name =:= Id],
    ok = bounds(Rectangle, Shape),
    [#{selector := Target, schemas := Schemas}] =
        [T || T = #{id := Name} <- Targets, Name =:= TargetId],
    Schema = element(1, Message),
    true = lists:member(Schema, Schemas),
    Candidates = [A || A = #{targets := Names} <- Bindings, lists:member(TargetId, Names)],
    [#{module := Module} | _] = Candidates,
    Selector = Module:pack_tag(Schema),
    Payload = hls_codec:align(Module:pack(Message), 32),
    Width = bit_size(Payload),
    true = Width =< 96,
    <<Value:Width/little>> = Payload,
    {X0, Y0, X1, Y1} = Rectangle,
    Packet = <<X0:16, Y0:16, X1:16, Y1:16, Target:2,
        (Width div 32):8, 0:16, Selector:8, Value:96>>,
    Recipients = [A || A = #{point := [X, Y]} <- Candidates,
        X0 =< X, X =< X1, Y0 =< Y, Y =< Y1],
    #{packet => Packet, recipients => Recipients}.

%% Reject wrapping or out-of-domain rectangles before any device is contacted.
-spec bounds({integer(), integer(), integer(), integer()}, [pos_integer()]) -> ok.
bounds({X0, Y0, X1, Y1}, [Width, Height])
        when X0 >= 0, X0 =< X1, X1 < Width, Y0 >= 0, Y0 =< Y1, Y1 < Height -> ok;
bounds(Rectangle, Shape) -> error({partition_rectangle, Rectangle, Shape}).
