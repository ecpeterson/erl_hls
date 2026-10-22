-module(hls_protocol_transport_topology).
-moduledoc "Three source actors with multiple ordered ports, independent recipients and external output.".
-export([topology/0, invalid/1]).
-doc "Returns a closed transport test topology; actors share complete two-phase source semantics.".
-spec topology() -> map().
topology() ->
    Ids = [a,b,c], Ports = [unaligned,full,constant,small,varying,conditional,partial,state_value],
    #{version => 1, actors => maps:from_list([{Id,hls_protocol_capture_fixture} || Id <- Ids]),
      families => #{}, ingresses => [], route_relations => [], startup => [],
      externals => [{monitor,out,[full]}],
      routes => [case Port of
          full -> {{Id,Port},[{external,monitor}]};
          unaligned -> {{Id,Port},buffered,[{actor,Next},{actor,Other}]};
          small -> {{Id,Port},[{actor,Other}]};
          _ -> {{Id,Port},[{actor,Next}]}
      end || {Id,Next,Other} <- [{a,b,c},{b,c,a},{c,a,b}], Port <- Ports]}.

-doc "Returns deliberately unsupported or incomplete topologies for production-command rejection tests.".
-spec invalid(coupled | missing_route) -> map().
invalid(coupled) ->
    T = #{routes := Routes} = topology(),
    T#{routes := [case R of {S,buffered,Rs} -> {S,coupled,Rs}; _ -> R end || R <- Routes]};
invalid(missing_route) ->
    T = #{routes := [_ | Routes]} = topology(),
    T#{routes := Routes}.
