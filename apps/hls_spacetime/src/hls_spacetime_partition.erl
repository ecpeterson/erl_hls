-module(hls_spacetime_partition).
-moduledoc """
Pure partition policy for proposed implementation plans.

The current deterministic policy balances stable logical actor identities across caller-supplied
targets. It does not assign transport lanes, codecs, runtime endpoints or physical device handles.
""".

-export([balanced/2]).

-doc "Assigns retained topology instances round-robin across unique logical target names. Rejects an empty or malformed target set.".
-spec balanced(hls_logical_topology:compact_plan(), [hls_implementation_plan:target(), ...]) ->
    hls_implementation_plan:placement().
balanced(Topology, [_ | _] = Targets) ->
    case length(Targets) =:= length(lists:usort(Targets)) of
        true -> lists:foreach(fun hls_logical_identity:validate/1, Targets);
        false -> error({duplicate_partition_targets, Targets})
    end,
    Instances = hls_logical_topology:instances(Topology),
    Count = length(Targets),
    maps:from_list([
        {Identity, lists:nth((Index rem Count) + 1, Targets)}
     || {Index, #{identity := Identity}} <- lists:enumerate(0, Instances)
    ]);
balanced(_Topology, Targets) ->
    error({invalid_partition_targets, Targets}).
