-module(xls_provider_lists).
-moduledoc "Compiler companion for hls_lists. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([transpile/3, dslx_imports/1, print_type/2, dslx_codec/2]).

%% TODO: bake new into record construction?

-doc "Lowers fixed-size collection operations. Descriptors and result sizes are static; dynamic bounds failures propagate as badarg.".
-spec transpile(
    list | nth | set | new | zero | sublist | array_slice,
    [xls_clause_lower:ir()],
    xls_clause_lower:clause_state()
) ->
    xls_clause_lower:ir()
    | xls_clause_lower:clause_state()
    | {fallible, badarg, xls_clause_lower:ir()}.
transpile(list, [{phantom, type, Subtype}, {static, integer, Count}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_lists:list(Subtype, Count)});
transpile(nth, [Index, List], _State) ->
    checked_element(Index, List, "collection_values[collection_index]");
transpile(set, [Index, List, Value], _State) ->
    checked_element(Index, List, ["update(collection_values, collection_index, ", Value, ")"]);
transpile(new, [Subtype, Count], State) ->
    NewState = transpile(list, [Subtype, Count], State),
    transpile(zero, [xls_clause_lower:reference(NewState)], NewState);
transpile(zero, [{phantom, type, {hls_type, hls_lists, list, [Subtype, Count]}}], _State) ->
    %% NOTE: Here we enforce that the arguments to `new/2` are static.
    ["zero!<", print_type(list, [Subtype, Count]), ">()"];
transpile(sublist, [Descriptor, List, Start, Count], _State) ->
    checked_slice_call(sublist, Descriptor, List, Start, Count);
transpile(array_slice, [Descriptor, List, Start, {static, integer, Length}], _State) when
    Length > 0
->
    checked_slice_call({array_slice, Length}, Descriptor, List, Start, {static, integer, Length});
transpile(array_slice, [_Descriptor, _List, _Start, {static, integer, 0}], _State) ->
    error(empty_xls_collection);
transpile(array_slice, [_Descriptor, _List, _Start, Length], _State) ->
    error({invalid_array_slice_length, Length}).

%% Bind a collection once, then retain checked access and the failure flag.
-spec checked_element(xls_clause_lower:ir(), xls_clause_lower:ir(), xls_dslx:value()) ->
    xls_type:result().
%% Keep element types at the call site: XLS currently emits invalid IR names
%% for type-generic functions instantiated with parameterized structs (including
%% APFloat, also nested in arrays). Bounds arithmetic lives in the static module.
%% TODO: move these typed operations into that module once XLS fixes its mangling.
checked_element(Index, List, Result) ->
    {fallible, badarg, [
        "{ let collection_values = ",
        List,
        "; ",
        "let (collection_index, collection_invalid) = hls_lists::checked_index<",
        "{array_size(collection_values)}>(",
        index(Index),
        "); (",
        Result,
        ", collection_invalid) }"
    ]}.

%% Retain the static collection shape while checking dynamic slice bounds.
-spec checked_slice_call(
    sublist | {array_slice, pos_integer()},
    xls_clause_lower:ir(),
    xls_clause_lower:ir(),
    xls_clause_lower:ir(),
    xls_clause_lower:ir()
) -> xls_type:result().
checked_slice_call(
    Operation,
    {phantom, type, Type = {hls_type, hls_lists, list, [Subtype, Size]}},
    List,
    Start,
    Count
) ->
    OutputSize =
        case Operation of
            sublist -> Size;
            {array_slice, Length} -> Length
        end,
    OutputType = print_type(list, [Subtype, OutputSize]),
    {fallible, badarg, [
        "{ let slice_values: ",
        xls_type:print_type(Type),
        " = ",
        List,
        "; let (slice_start, slice_mask, slice_invalid) = hls_lists::slice_bounds<u32:",
        integer_to_list(Size),
        ", u32:",
        integer_to_list(OutputSize),
        ">(",
        index(Start),
        ", ",
        index(Count),
        "); ",
        "let sliced = array_slice(slice_values, slice_start, zero!<",
        OutputType,
        ">()); ",
        "let selected = for (i, result): (u32, ",
        OutputType,
        ") in u32:0..u32:",
        integer_to_list(OutputSize),
        " { update(result, i, if slice_mask[i] { sliced[i] } ",
        "else { zero!<",
        xls_type:print_type(Subtype),
        ">() }) } (zero!<",
        OutputType,
        ">()); (selected, slice_invalid) }"
    ]}.

%% Preserve literal width and signedness before collection bounds checks.
-spec index(xls_clause_lower:ir()) -> xls_clause_lower:ir().
%% Preserve a literal's full value before checking bounds. Dynamic expressions
%% keep their inferred integer width and signedness too.
index({static, integer, Value}) when Value >= 0, Value =< 16#ffffffff ->
    ["u32:", integer_to_list(Value)];
index({static, integer, Value}) ->
    Width = max(32, bit_size(binary:encode_unsigned(abs(Value))) + 1),
    [xls_nums:signed_type(Width), ":", integer_to_list(Value)];
index(Value) ->
    Value.

-spec dslx_imports([atom()]) -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports(Names) ->
    case lists:any(fun(Name) -> lists:member(Name, [nth, set, sublist, array_slice]) end, Names) of
        true -> [hls_bits, hls_lists];
        false -> [hls_bits]
    end.

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
print_type(list, [Subtype, Count]) when Count > 0 ->
    [xls_type:print_type(Subtype), "[", integer_to_list(Count), "]"];
print_type(list, [_Subtype, 0]) ->
    error(empty_xls_collection).

-spec dslx_codec(atom(), [hls_type:arg()]) -> xls_type:codec().
-doc "Converts wire bits and DSLX values using the provider encoding, including nested padding.".
dslx_codec(list, [Subtype, Count]) ->
    %% XLS cannot bit-cast a flattened value into a multidimensional array.
    %% Compose element codecs at every dimension; these static maps are wires.
    BitsType = ["bits[", integer_to_list(hls_type:width(Subtype)), "]"],
    ArrayType = print_type(list, [Subtype, Count]),
    {
        fun(Bits) ->
            codec_map(
                ["hls_bits::to_stream(", Bits, ") as ", BitsType, "[", integer_to_list(Count), "]"],
                ArrayType,
                Count,
                fun(V) ->
                    xls_type:dslx_from_bits(
                        Subtype,
                        ["hls_bits::from_stream(", V, ")"]
                    )
                end
            )
        end,
        fun(Values) ->
            [
                "hls_bits::from_stream((",
                codec_map(
                    Values,
                    [BitsType, "[", integer_to_list(Count), "]"],
                    Count,
                    fun(V) -> ["hls_bits::to_stream(", xls_type:dslx_to_bits(Subtype, V), ")"] end
                ),
                ") as bits[",
                integer_to_list(hls_type:width(Subtype) * Count),
                "])"
            ]
        end
    }.

%% Bind the input before converting each element so nested codecs cannot capture its index.
-spec codec_map(xls_dslx:value(), xls_dslx:value(), pos_integer(), fun(
    (xls_dslx:value()) -> xls_dslx:value()
)) -> xls_dslx:value().
%% Bind input before entering the loop so recursively nested codecs may reuse
%% these local names without capturing an enclosing array's index.
codec_map(Input, OutputType, Count, Convert) ->
    [
        "{ let codec_input = ",
        Input,
        "; for (codec_index, codec_output): (u32, ",
        OutputType,
        ") in u32:0..u32:",
        integer_to_list(Count),
        " { update(codec_output, codec_index, ",
        Convert(["codec_input[u32:", integer_to_list(Count - 1), " - codec_index]"]),
        ") } (zero!<",
        OutputType,
        ">()) }"
    ].
