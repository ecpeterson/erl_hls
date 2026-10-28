-module(xls_partition_application).
-moduledoc "DSLX application shell connecting a checked partition graph to RAM, device links and its framed gateway. Consumes build-time bindings; runtime packet handling remains in hls_partition_wire.".

-export([emit/3]).

-doc "Wraps a generated device graph with the static routed application gateway; link ports remain separate. Rejects ordinary layouts above the fixed eight-word event envelope before rendering.".
-spec emit(map(), term(), atom()) -> iolist().
emit(#{devices := Devices}, Device, Graph) ->
    #{identity := Identity, host := Host, control := Control,
      local := Local = #{ingresses := [#{input_name := Input}],
        externals := Externals}} = maps:get(Device, Devices),
    Words = hls_frame_layout:payload_words(maps:get(frame_layout, Local)),
    case Words =< 8 of
        true -> ok;
        false -> hls_diagnostic:raise(partition, gateway_payload_capacity,
            <<"The partition application gateway supports at most eight payload words.">>,
            #{payload_words => Words, maximum => 8})
    end,
    IdentityArgs = lists:join(", ", ["u64:" ++ integer_to_list(Word) || <<Word:64/little>> <= Identity]),
    Tile = maps:get(tile, Local, false),
    Count = length(Externals),
    RamParameters = hls_partition_shared_dslx:parameters(Local),
    RamNames = hls_partition_shared_dslx:names(Local),
    ConfigParameters = hls_partition_tile:parameters(Local) ++ case Tile of
        true -> ["tile_gateway: chan<bits[272]> in", "tile_host: chan<u16> in"]; false -> [] end,
    Args = lists:join(", ", hls_partition_links:frame_arguments(Local) ++
        ["events_p[u32:" ++ integer_to_list(I) ++ "]" || I <- lists:seq(0, Count-1)] ++ [Input ++ "_c"] ++ RamNames ++ hls_partition_tile:names(Local)),
    ["import axis;\n", hls_partition_links:imports(Local), case Tile of true -> "import hls_partition_tile_io;\n"; false -> [] end, "import hls_spatial_router;\nimport hls_partition_io;\nimport ", atom_to_list(Graph), ";\n\n",
     [["import ", atom_to_list(M), ";\n"] || M <- lists:usort([Module || #{module := Module} <- maps:get(schedulers, Local)])],
     "pub proc Top {\n",
     "  config(", lists:join(",\n      ", hls_partition_links:parameters(Local)), ",\n",
     "      app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out",
     [[",\n      ", P] || P <- RamParameters ++ ConfigParameters], ") {\n",
     hls_partition_links:frame_channels(Local),
     "    let (events_p, events_c) = chan<axis::Frame, u32:1>[", integer_to_list(Count), "](\"events\");\n",
     "    let (", Input, "_p, ", Input, "_c) = chan<hls_spatial_router::SpatialFrame, u32:1>(\"control\");\n",
     "    spawn ", atom_to_list(Graph), "::Top(", Args, ");\n",
     hls_partition_links:spawn(Local),
     case Tile of
        true -> ["    spawn hls_partition_tile_io::Boundary<u32:", integer_to_list(Count), ", u16:", integer_to_list(Control),
            ">(tile_gateway, tile_host, app_in, app_out, ", Input, "_p, events_c);\n"];
        false -> ["    spawn hls_partition_io::Boundary<u32:", integer_to_list(Count), ", ",
            IdentityArgs, ", u16:", integer_to_list(Host), ", u16:", integer_to_list(Control),
            ">(app_in, app_out, ", Input, "_p, events_c);\n"]
     end,
     "    ()\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"].
