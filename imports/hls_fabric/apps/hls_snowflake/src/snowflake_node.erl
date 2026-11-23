-module(snowflake_node).
%% Adapted from localuf's MIT-licensed Snowflake transitions; see ../reference/LICENSE.localuf.
-moduledoc """
Bounded Snowflake transitions for repetition and planar surface-code vertices.

The 2:1 growth schedule, fast merger and full unrooting match localuf
v3.4.4. Repetition visits W/E/D/U; the phenomenological surface graph
visits N/W/D/U/E/S. Neighbors are snapshots from the start
of a merging step. Flooding changes this vertex's pointer before syncing;
the returned nonzero transfer direction moves one defect and toggles one
correction edge. The caller XOR-combines all transfers before committing.
These functions contain no scheduler, memory layout or transport policy.
""".
-export([reset/1, drop/4, grow/3, merge/9, merge_surface/11]).
-export_type([vertex/0]).
-compile({parse_transform, hls_pack}).
-include("snowflake_node.hrl").
-hls_data(node).
-hls_tags([]).

-doc "Finite vertex state; cid=-1 is the full-unrooting marker.".
-type vertex() :: #node{}.

-include("snowflake_node_impl.hrl").
