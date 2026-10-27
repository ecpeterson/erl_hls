-module(xls_shared_machine_layout).
-moduledoc "The complete physical actor row shared by codecs, RAM bindings and passive inspection. Optional storage has zero-width fields at its ordered position.".
-export([new/1, from_spec/1, from_group/1, width/1, field/2, fields/1]).
-export_type([widths/0, name/0, field/0, layout/0, descriptor/0]).

-doc "Physical storage dimensions; data is required, and absent private facilities occupy zero bits.".
-type widths() :: #{data := non_neg_integer(), reduction => non_neg_integer(),
    gather => non_neg_integer(), next_event => 0 | 8, replies => non_neg_integer()}.

-doc "Fields in low-to-high physical order; every name is present even when its width is zero.".
-type name() :: phase | entered_from | data | enter_pending | failure |
    reduction | gather | next_event | replies.

-doc "A numeric low-bit offset and serialized width within the complete row.".
-type field() :: #{offset := non_neg_integer(), width := non_neg_integer()}.

-doc "A typed least-significant-field-first schema accepted directly by xls_struct_codec.".
-type layout() :: xls_struct_codec:layout().

-doc "The complete row width and named slices, suitable for RAM and inspection manifests.".
-type descriptor() :: #{width := pos_integer(), phase := field(), entered_from := field(),
    data := field(), enter_pending := field(), failure := field(), reduction := field(),
    gather := field(), next_event := field(), replies := field()}.

-doc "Builds the ordered physical row from checked widths. Zero-width fields remain present and do not advance the offset; the event selector occupies either zero or eight bits.".
-spec new(widths()) -> layout().
new(Widths = #{data := Data}) ->
    Event = maps:get(next_event, Widths, 0),
    true = Event =:= 0 orelse Event =:= 8,
    xls_struct_codec:layout([{Name, raw_type(Bits)} || {Name, Bits} <-
        [{phase, 8}, {entered_from, 8}, {data, Data}, {enter_pending, 1}, {failure, 16},
         {reduction, maps:get(reduction, Widths, 0)}, {gather, maps:get(gather, Widths, 0)},
         {next_event, Event}, {replies, maps:get(replies, Widths, 0)}]], lsb).

-doc "Derives the complete row from a checked actor specification, including projected data, physical gather storage, internal events and retained callers.".
-spec from_spec(map()) -> layout().
from_spec(Spec) ->
    Replies = xls_statem_reply_codegen:width(Spec),
    Event = case maps:get(continuations, Spec, []) =/= [] orelse Replies > 0 of
        true -> 8;
        false -> 0
    end,
    new(#{data => xls_state_projection:width(Spec),
        reduction => xls_statem_reduction_codegen:private_width(maps:get(reductions, Spec, none)),
        gather => xls_shared_gather_codegen:storage_width(Spec),
        next_event => Event, replies => Replies}).

-doc "Derives the same complete row from a normalized scheduler group's retained physical dimensions; no actor source or interface is loaded.".
-spec from_group(map()) -> layout().
from_group(Group = #{state := #{width := Data}}) ->
    new(#{data => maps:get(physical_data_width, Group, Data),
        reduction => maps:get(reduction_storage_width, Group, 0),
        gather => maps:get(gather_storage_width, Group, 0),
        next_event => maps:get(continuation_width, Group, 0),
        replies => maps:get(reply_storage_width, Group, 0)}).

-doc "Returns the complete physical width, including every optional tail field.".
-spec width(layout()) -> pos_integer().
width(#{width := Width}) -> Width.

-doc "Returns a named row slice, including zero-width slices for absent private facilities.".
-spec field(layout(), name()) -> field().
field(#{fields := Fields}, Name) ->
    [#{prefix := Offset, width := Width}] = [F || F = #{name := N} <- Fields, N =:= Name],
    #{offset => Offset, width => Width}.

-doc "Returns the complete width and every named slice without exposing type-provider descriptors.".
-spec fields(layout()) -> descriptor().
fields(#{width := Width, fields := Fields}) ->
    (maps:from_list([{Name, #{offset => Offset, width => Bits}} ||
        #{name := Name, prefix := Offset, width := Bits} <- Fields]))#{width => Width}.

%% Numeric fields use native bits; an empty stream supplies the existing zero-width type.
-spec raw_type(non_neg_integer()) -> hls_type:descriptor().
raw_type(0) -> hls_bits:bits(0);
raw_type(Width) when Width > 0 -> hls_nums:uN(Width).
