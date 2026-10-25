-module(hls_protocol_identity_fixture).
-moduledoc "Small topology variants for source-build identity regressions; no decoder workload.".
-include("hls_protocol_identity_fixture.hrl").
-export([topology/1]).

-doc "Retains integer, numeric-atom and tuple endpoint identities; the variant changes one declared startup message without changing the wire schema.".
-spec topology(default | changed_startup) -> map().
topology(Variant) ->
    T = #{externals := Externals, routes := Routes} = hls_protocol_boundary_fixture:topology(),
    Ids = #{shared => {bucket, 1}, single => 3, unused => '3'},
    Initial = case Variant of default -> ?IDENTITY_STARTUP_ID; changed_startup -> 17 end,
    T#{startup := [{c, [{cfg, Initial}]}, {d, [{cfg, 4}]}],
       externals := [{maps:get(Id, Ids), Direction, Schemas} || {Id, Direction, Schemas} <- Externals],
       routes := [{From, [{external, maps:get(Id, Ids)}]} || {From, [{external, Id}]} <- Routes]}.
