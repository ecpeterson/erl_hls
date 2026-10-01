-module(hls_partition_links).
-moduledoc "Independent point-to-point credit bridges for a partition's physical peers.".
-export([configure/2, width/1, imports/1, ports/1, parameters/1, frame_parameters/1, frame_names/1,
    frame_channels/1, frame_arguments/1, channel/3, spawn/1]).
-export_type([transport/0]).

-doc "Serial one-credit words, or packed transfers containing 1/2/4 words with 1–16 receive slots per lane. Optional compact framing preserves every frame bit. Both peers share this setting.".
-type transport() :: serial | #{words := 1 | 2 | 4, credits := 1..16, compact => boolean()}.

-doc "Sets every peer link's transport before generating hardware and deployment identities. Rejects unsupported widths, capacities and extra keys.".
-spec configure(map(), transport()) -> map().
configure(Partition, serial) -> maps:remove(transport, Partition);
configure(Partition, #{compact := Compact} = Transport)
        when map_size(Transport) =:= 3, is_boolean(Compact) ->
    Configured = #{transport := Plain} = configure(Partition, maps:remove(compact, Transport)),
    Configured#{transport => case Compact of true -> Plain#{compact => true}; false -> Plain end};
configure(Partition, #{words := Words, credits := Credits} = Transport)
        when map_size(Transport) =:= 2, is_integer(Credits), Credits >= 1, Credits =< 16,
             (Words =:= 1 orelse Words =:= 2 orelse Words =:= 4) ->
    Partition#{transport => Transport};
configure(_Partition, Transport) -> error({partition_transport, Transport}).

-doc "Returns the physical ready/valid transfer width, including internal validity and packet-boundary sidebands.".
-spec width(map()) -> pos_integer().
width(#{transport := #{words := Words}}) -> 34*Words;
width(_) -> 33.

-doc "Returns the static DSLX import required by the selected transport.".
-spec imports(map()) -> iolist().
imports(#{transport := #{}}) -> "import hls_packed_link;\n";
imports(_) -> "import hls_credit_link;\n".

-doc "Returns stable ready/valid RTL ports in peer-index order; each peer owns one duplex stream and fault output.".
-spec ports(map()) -> [{string(), pos_integer(), in | out}].
ports(Local = #{links := Links}) ->
    Width = width(Local),
    lists:append([[{"_link_" ++ integer_to_list(I) ++ "_in", Width, in},
        {"_link_" ++ integer_to_list(I) ++ "_out", Width, out},
        {"_fault_" ++ integer_to_list(I) ++ "_out", 32, out}]
        || #{index := I} <- Links]).

-doc "Returns DSLX channel parameters matching the device's physical link ports.".
-spec parameters(map()) -> [iolist()].
parameters(Local) ->
    [[Name, ": chan<", case Width of 33 -> "axis::Beat"; 32 -> "u32";
        _ -> ["bits[", integer_to_list(Width), "]"] end,
        "> ", atom_to_list(Direction)] || {[$_ | Name], Width, Direction} <- ports(Local)].

-doc "Returns per-peer frame-array declarations for the actor graph.".
-spec frame_parameters(map()) -> [iolist()].
frame_parameters(#{links := Links}) ->
    lists:append([[frame_name(I, in) ++ ": chan<axis::Frame>[u32:" ++ integer_to_list(length(Rx)) ++ "] in",
        frame_name(I, out) ++ ": chan<axis::Frame>[u32:" ++ integer_to_list(length(Tx)) ++ "] out"]
        || #{index := I, tx_lanes := Tx, rx_lanes := Rx} <- Links]).

-doc "Returns graph member names in the same order as its frame parameters.".
-spec frame_names(map()) -> [string()].
frame_names(#{links := Links}) ->
    lists:append([[frame_name(I, in), frame_name(I, out)] || #{index := I} <- Links]).

-doc "Allocates independent lane queues. Each peer uses the largest depth needed for its lanes, including consolidated reduction storage.".
-spec frame_channels(map()) -> iolist().
frame_channels(Local = #{links := Links, rx_lanes := Incoming}) ->
    lists:append([[received_array("received_" ++ integer_to_list(I),
        [L || L = #{source_device := D} <- Incoming, D =:= Peer], Local),
        array("outgoing_" ++ integer_to_list(I), length(Tx))]
        || #{index := I, peer := Peer, tx_lanes := Tx} <- Links]).

-doc "Returns local channels in graph parameter order, without multiplexing peers.".
-spec frame_arguments(map()) -> [string()].
frame_arguments(#{links := Links}) ->
    lists:append([["received_" ++ integer_to_list(I) ++ "_c", "outgoing_" ++ integer_to_list(I) ++ "_p"]
        || #{index := I} <- Links]).

-doc "Selects a lane's peer array and wire index within the local actor graph.".
-spec channel(map(), map(), in | out) -> iolist().
channel(#{links := Links}, Lane = #{wire_id := Wire}, Direction) ->
    Peer = maps:get(case Direction of in -> source_device; out -> destination_device end, Lane),
    [Index] = [I || #{index := I, peer := P} <- Links, P =:= Peer],
    [frame_name(Index, Direction), "[u32:", integer_to_list(Wire), "]"].

-doc "Connects one credit bridge per peer. Both directions must have at least one lane.".
-spec spawn(map()) -> iolist().
spawn(Local = #{links := Links}) ->
    [bridge(Link, maps:get(transport, Local, serial)) || Link <- Links].

%% Pass whole allocated channel arrays: the pinned XLS rejects arrays assembled from channels.
-spec bridge(map(), transport()) -> iolist().
bridge(#{index := Index, peer := Peer, tx_lanes := Tx, rx_lanes := Rx}, Transport) ->
    case {Tx, Rx} of
        {[_ | _], [_ | _]} -> ok;
        _ -> error({unidirectional_partition_link, Peer})
    end,
    I = integer_to_list(Index),
    {Module, Extra} = case Transport of
        serial -> {"hls_credit_link", []};
        #{words := Words, credits := Credits} -> {"hls_packed_link",
            [", u32:", integer_to_list(Words), ", u32:", integer_to_list(Credits),
                case maps:get(compact, Transport, false) of true -> ", true"; false -> [] end]}
    end,
    ["    spawn ", Module, "::Bridge<u32:", integer_to_list(length(Tx)),
        ", u32:", integer_to_list(length(Rx)), ", u16:18512", Extra, ">(link_", I, "_in, link_", I,
        "_out, outgoing_", I, "_c, received_", I, "_p, fault_", I, "_out);\n"].

%% One naming rule serves graph declarations and source/recipient connections.
-spec frame_name(non_neg_integer(), in | out) -> string().
frame_name(Index, Direction) -> "remote_" ++ integer_to_list(Index) ++ "_" ++ atom_to_list(Direction).

%% Channel storage is unchanged by splitting the original aggregate into peers.
-spec array(string(), non_neg_integer()) -> iolist().
array(Name, Count) ->
    ["    let (", Name, "_p, ", Name, "_c) = chan<axis::Frame, u32:1>[",
        integer_to_list(Count), "](\"", Name, "\");\n"].

%% Pinned XLS rejects an array assembled from scalar Frame channels
%% (FrameN<u32:3> versus FrameN<3>). Use the largest required per-peer depth.
-spec received_array(string(), [map()], map()) -> iolist().
received_array(Name, Lanes, Local) ->
    Depth = 1 + lists:max([0 | [hls_partition_reduction:queue_extra(Id, Local)
        || #{id := Id} <- Lanes]]),
    ["    let (", Name, "_p, ", Name, "_c) = chan<axis::Frame, u32:",
     integer_to_list(Depth), ">[", integer_to_list(length(Lanes)), "](\"", Name, "\");\n"].
