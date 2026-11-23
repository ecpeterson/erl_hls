-module(hls_protocol_composition_fixture).
-moduledoc "Small placement failures for composition planning, using existing source actor behaviors.".
-export([beam_to_beam/0, isolated_role/0]).

-doc "Keeps native left's incoming and outgoing crossings while right sends only to the BEAM-owned sink. Every producer has one recipient, isolating the unsupported host-to-host route from multicast rejection.".
-spec beam_to_beam() -> map().
beam_to_beam() ->
    Topology = #{routes := Routes} = hls_protocol_network_fixture:framed(),
    Topology#{routes := [case Route of
        {From, buffered, [First | _]} -> {From, [First]};
        _ -> Route
    end || Route <- Routes]}.

-doc "Adds a final isolated producer role without changing the two valid communicating roles. Its absence of crossing links must reject the complete deployment before any role is rendered.".
-spec isolated_role() -> map().
isolated_role() ->
    Topology = #{actors := Actors, routes := Routes, externals := Externals} =
        hls_protocol_network_fixture:framed(),
    Topology#{actors := Actors#{orphan => hls_protocol_network_fixture},
        externals := Externals ++ [{orphan, out, [value, go, total]}],
        routes := Routes ++ [{{orphan, Port}, [{external, orphan}]} || Port <- [early, open, later]]}.
