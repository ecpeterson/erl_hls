-module(hls_protocol_link).
-moduledoc "Groups typed capture links by their exact payload widths. Capacity and delivery precedence are separate contracts.".
-export([components/1]).

-doc "Groups all actual sender/destination pairs by their ordered payload widths. Keeps every source/channel association in the returned instances; only byte-identical structural shapes share a component. Zero-bit payloads use one tied dummy bit. Application capacity and progress remain obligations.".
-spec components(map()) -> [map()].
components(#{pairs:=Pairs}) ->
    Shapes=lists:usort([widths(P)||P<-Pairs]),
    [#{id=>I,widths=>Widths,instances=>[P||P<-Pairs,widths(P)=:=Widths]}
        || {I,Widths}<-lists:enumerate(0,Shapes)].

%% Static channel order is inherited exactly from the per-sender catalogue.
-spec widths(map()) -> [pos_integer()].
widths(#{slots:=Slots}) ->
    true = length(Slots) > 0 andalso length(Slots) < 256,
    [max(1,W)||#{payload_bits:=W}<-Slots].
