-module(hls_protocol_application_codec).
-moduledoc """
Protocol stream owners use these control and event codecs after application binding. hls_protocol_application_binding supplies the retained schema views; this module delegates geometry and packing to partition wire helpers.

Runtime command selection and external-event decoding over retained application schemas. Accepts trusted local bindings, not source programs or planner artifacts; current compatible record providers perform packing.
""".

%% No source loading, topology derivation or hardware rendering occurs in these codecs.
%% Application control selection and delivery.
-export([control/2, delivery/2]).
%% External event decoding.
-export([event/4]).

-doc "Encodes a typed rectangle using the checked source schemas. All selected devices must share the same command bytes. The relay broadcasts those global bounds; each native sparse mask discards unowned targets. An empty selection or malformed command is rejected before queue admission.".
-spec control(hls_protocol_application_schema:control_view(), hls_partition_wire:rectangle()) ->
    binary().
control(Application, Command) ->
    {Payload, _, _} = delivery(Application, Command),
    Payload.

-doc "Returns one checked command payload, its exact global actor indices and the original record. Uses the shared partition selector for schema packing and geometry; host owners filter these indices by actual local ownership. Rejects empty selection before queue admission. No transport or actor delivery occurs here.".
-spec delivery(hls_protocol_application_schema:control_view(), hls_partition_wire:rectangle()) ->
    {binary(), [non_neg_integer()], tuple()}.
delivery(#{partition := Partition}, {Ingress, Target, Bounds, Record}) ->
    #{packet := Packet, recipients := Recipients = [_ | _]} =
        hls_partition_ingress:select(Partition, Ingress, Target, Bounds, Record),
    {
        hls_partition_wire:control_payload(Packet),
        [maps:get(index, Actor) || Actor <- Recipients],
        Record
    }.

-doc "Decodes a canonical external frame at the emitted global endpoint index, using only the emitting device's producer schemas. Rejects unknown selectors, wrong word counts and noncanonical padding. This is codec validation, not application-semantic validation.".
-spec event(
    hls_protocol_application_schema:event_view(),
    hls_protocol_application_schema:device(),
    byte(),
    non_neg_integer()
) ->
    {hls_protocol_application_schema:id(), tuple()}.
event(#{devices := Devices}, Device, Index, Frame) ->
    Binding = #{host := Host, events := Events, frame_layout := Layout} = maps:get(Device, Devices),
    Port = "external_" ++ integer_to_list(Index),
    [Endpoint] = [E || {E, #{port := P}} <- maps:to_list(Events), P =:= Port],
    {#{op := Tag, txid := 0, flags := 0}, Payload} = hls_frame_layout:unpack_integer(Layout, Frame),
    hls_partition_wire:event(Binding, {Endpoint, Host}, {Tag, 0, 0}, Payload).
