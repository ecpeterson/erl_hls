-module(hls_field_layout).
-moduledoc "Ordered field widths and offsets shared by host framing and compiler renderers. This module derives layout from runtime type descriptors; it emits no target code.".
%% Schema layout construction.
-export([layout/2]).
%% Shared serialized layout contract.
-export_type([layout/0, encoding/0, field/0]).

-doc "Stream fields follow Erlang bitstring order; lsb fields occupy ascending numeric slices.".
-type encoding() :: stream | lsb.

-doc "Named type and its serialized width and prefix within the containing record.".
-type field() :: #{
    name := atom(),
    type := hls_type:descriptor(),
    prefix := non_neg_integer(),
    width := non_neg_integer()
}.

-doc "Ordered typed fields and their cumulative serialized widths. Prefix is a physical-stream offset for stream encoding and a numeric low-bit offset for lsb encoding.".
-type layout() :: #{
    encoding := encoding(),
    width := non_neg_integer(),
    fields := [field()]
}.

-doc "Derives a layout from unique caller-checked field names and provider descriptors. Zero-width fields remain present and do not advance the prefix.".
-spec layout(hls_record:fields(), encoding()) -> layout().
layout(Fields, Encoding) when Encoding =:= stream; Encoding =:= lsb ->
    {Slots, Width} = lists:mapfoldl(
        fun({Name, Type}, Prefix) ->
            Bits = hls_type:width(Type),
            {#{name => Name, type => Type, prefix => Prefix, width => Bits}, Prefix + Bits}
        end,
        0,
        Fields
    ),
    #{encoding => Encoding, width => Width, fields => Slots}.
