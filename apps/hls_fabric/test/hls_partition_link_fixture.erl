-module(hls_partition_link_fixture).
-moduledoc "Small generated four-peer endpoint for RTL isolation and lane-identity checks.".
-export([write/1]).

-doc "Writes the production bridge connectivity with two independent frame lanes per peer.".
-spec write(file:filename()) -> ok.
write(File) ->
    Local = #{links => [#{index => I, peer => I+1,
        tx_lanes => [#{wire_id => 0}, #{wire_id => 1}],
        rx_lanes => [#{wire_id => 0}, #{wire_id => 1}]} || I <- lists:seq(0, 3)]},
    Frames = lists:append([["outgoing_" ++ integer_to_list(I) ++ "_c: chan<axis::Frame>[u32:2] in",
        "received_" ++ integer_to_list(I) ++ "_p: chan<axis::Frame>[u32:2] out"] || I <- lists:seq(0, 3)]),
    file:write_file(File, ["import axis;\nimport hls_credit_link;\npub proc Top {\n  config(",
        lists:join(",\n      ", hls_partition_links:parameters(Local) ++ Frames), ") {\n",
        hls_partition_links:spawn(Local), "    ()\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"]).
