-module(hls_partition_binding).
-moduledoc "Build-time derivation of per-device host endpoints and retained event schemas from checked partition ownership. The resulting descriptors are consumed by hls_partition_wire without reacquiring topology or source interfaces.".

-export([deployment/1, binding/4]).

%% Fixed application-gateway bindings, unrelated to actor IDs or geometry.
%% The values are arbitrary; the XLS gateway shares FIRST_EVENT_ENDPOINT.
-define(CONTROL_ENDPOINT, 7).
-define(FIRST_EVENT_ENDPOINT, 8).

-doc "Derives fixed control/event endpoints and a per-device SHA-256 identity covering placement, startup and wire bindings.".
-spec deployment(map()) -> map().
deployment(Partition = #{devices := Devices}) ->
    #{partition => Partition, devices => maps:from_list([begin
        Local = hls_partition:device(Partition, Device),
        {Device, (binding(Partition, Device, Host, Local))#{local => Local}}
    end || {Host, Device} <- lists:enumerate(1, Devices)])}.

-doc "Binds one device's declared ingress and external codecs to shared endpoints. The caller must supply checked producer encodings and local port order; this does not validate a runtime implementation. Identity covers the supplied partition and derived wire binding.".
-spec binding(map(), term(), 1 .. ((1 bsl 16) - 1), map()) -> map().
binding(Partition, Device, Host, #{ingresses := [#{id := Ingress}], externals := Externals})
        when Host > 0, Host < 65536 ->
    true = length(Externals) > 0,
    Events = maps:from_list([{?FIRST_EVENT_ENDPOINT + Index, external(Partition, Device, E)}
        || {Index, E} <- lists:enumerate(0, Externals),
           Index < (1 bsl 16) - ?FIRST_EVENT_ENDPOINT]),
    true = map_size(Events) =:= length(Externals),
    Binding = #{host => Host, control => ?CONTROL_ENDPOINT, ingress => Ingress, events => Events},
    Identity = crypto:hash(sha256, term_to_binary(
        {partition_application, 1, Partition, Device, Binding}, [deterministic])),
    Binding#{identity => Identity}.

%% All producers of an external already agree on each schema's representation.
-spec external(map(), term(), map()) -> map().
external(#{actors := Actors, routes := Routes}, Device, #{id := Id, port := Port}) ->
    Producers = [{Actor, Output} || #{source := {Id0, Output}, recipients := Recipients} <- Routes,
        lists:member({external, Id}, Recipients),
        Actor = #{identity := A, device := D} <- Actors, A =:= Id0, D =:= Device],
    Schemas = lists:append([[begin
        Schema = #{selector := Selector} = maps:get(Name, Codecs),
        {Selector, Schema}
    end || Name <- maps:get(Output, Outputs, [])]
        || {#{schemas := Codecs, output_schemas := Outputs}, Output} <- Producers]),
    #{id => Id, port => Port, schemas => maps:from_list(Schemas)}.
