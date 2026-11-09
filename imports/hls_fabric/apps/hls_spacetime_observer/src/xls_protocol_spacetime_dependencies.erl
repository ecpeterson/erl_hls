-module(xls_protocol_spacetime_dependencies).
-moduledoc "Reconstructs selected operational operands from a build-bound scalar XLS graph. The observer planner calls plan/3; capture interpretation supplies one sample/2 per pre-edge clock, then asks write/3 or read/4 for register-bit dependencies. Unsupported expressions and missing observations remain explicit roots. This does not identify sensitized gates, native switching or routed paths.".

%% Offline planning and bounded per-clock interpretation.
-export([plan/3, signals/1, registers/1, sample/2, write/3, read/4]).
-export_type([plan/0, sample/0, result/0, register/0]).

%% Only flat literal arrays are admitted, with fixed aggregate entry/bit budgets.
-type table() :: #{width := pos_integer(), count := pos_integer(), values := tuple()}.
%% Only scalar nodes participate; tuple/channel boundaries need checked input bindings.
-type scalar_node() :: #{
    name := binary(),
    width := pos_integer(),
    op := binary(),
    args := [binary()],
    attrs := #{binary() => binary()},
    table => table(),
    index => binary(),
    arg_widths => [pos_integer()],
    bit_mask => non_neg_integer(),
    literal_value => non_neg_integer(),
    slice_start => non_neg_integer(),
    choices => [binary()],
    default_case => binary() | none
}.
%% A native signal binding distinguishes stored state from an external sampled input.
-type binding() :: #{
    kind := state | input,
    signal := binary(),
    width := pos_integer(),
    state_element => binary(),
    equivalent_state => binary()
}.
%% One XLS state update and its optional guard.
-type update() :: #{node := binary(), value := binary(), predicate := binary() | unconditional}.
-doc "An observed emitted register and its exact data/enable expressions. Unknown state bindings retain empty updates and an explicit binding_status.".
-type register() :: #{
    name := binary(),
    width := pos_integer(),
    data => binary(),
    enable => binary(),
    rule => atom(),
    ir_state => binary(),
    updates => [update()],
    binding_status => supported | unknown
}.
-doc "An exact IR/RTL-bound scalar program, its observed leaves, state updates and required passive input taps. Planning caps input size, nodes and scalar width; unsupported operations remain opaque nodes.".
-type plan() :: #{
    schema := 1,
    inputs := #{optimized_ir := binary(), rtl := binary()},
    nodes := #{binary() => scalar_node()},
    order := [binary()],
    bindings := #{binary() => binding()},
    registers := [register()],
    signals := [xls_protocol_spacetime:signal()]
}.
-doc "Scalar values computed once for one pre-edge clock; unknown values never select a guessed branch.".
-type sample() :: #{values := #{binary() => non_neg_integer() | unknown}}.
-doc "Selected data/control masks keyed by emitted register name, computed result when available, selected state updates and unresolved operand descriptors. Masks describe logical operational inputs, not native enables or electrical influence.".
-type result() :: #{
    value := non_neg_integer() | unknown,
    data_masks := #{binary() => non_neg_integer()},
    control_masks := #{binary() => non_neg_integer()},
    selected := [binary()],
    unknown := [binary()]
}.
%% Each query visits only new bits per node/role; targets never share traversal state.
-type walk() :: #{
    data_masks := #{binary() => non_neg_integer()},
    control_masks := #{binary() => non_neg_integer()},
    unknown := [binary()],
    seen := #{{binary(), data | control} => non_neg_integer()},
    visits := non_neg_integer()
}.

-define(MAX_NODES, 100000).
-define(MAX_WIDTH, 4096).
-define(MAX_BYTES, 32 * 1024 * 1024).
-define(MAX_VISITS, 100000).
-define(MAX_DEPTH, 2048).
-define(MAX_TABLE_ENTRIES, 65536).
-define(MAX_TABLE_BITS, 1024 * 1024).

-doc "Parses generated optimized XLS scalar nodes and next_value operations, checking state leaves against supplied exact RTL registers. Coalesced states may share one observed representative when one proc gives them identical widths, initial literals and sole guarded updates. External scalar tuple reads require matching received tuples and RTL slices. Rejects malformed/duplicate nodes and exceeded fixed limits; unsupported forms remain unknown. Flat literal tables are bounded to 65,536 entries and 1,048,576 bits. Input binaries are retained through SHA-256 identities.".
-spec plan(binary(), binary(), [register()]) -> plan().
plan(Ir, Rtl, Registers) when byte_size(Ir) =< ?MAX_BYTES, byte_size(Rtl) =< ?MAX_BYTES ->
    Lines = binary:split(Ir, <<"\n">>, [global]),
    ScalarNodes = [
        parse_node(Name, Width, Op, Body)
     || Line <- Lines,
        [Name, Width, Op, Body] <- captures(
            Line, <<"^  ([A-Za-z_][A-Za-z_0-9.]*): bits\\[([0-9]+)\\] = ([a-z_]+)\\((.*)\\)$">>, [
                1, 2, 3, 4
            ]
        )
    ],
    true = length(ScalarNodes) =< ?MAX_NODES,
    Tables = parse_tables(Lines),
    true = length(ScalarNodes) + map_size(Tables) =< ?MAX_NODES,
    Nodes = [bind_table(N, Tables) || N <- ScalarNodes],
    RawIndex = unique_nodes(Nodes),
    Index = maps:map(fun(_, N) -> normalize_node(N, RawIndex) end, RawIndex),
    DirectState = state_bindings(Nodes, Registers, Rtl),
    Updates = parse_updates(Lines),
    State = equivalent_states(Nodes, DirectState, Updates, initial_state(Lines)),
    Inputs = input_bindings(Nodes, Lines, Rtl),
    Bindings = maps:merge(State, Inputs),
    BoundRegisters = [bind_register(R, DirectState, Updates) || R <- Registers],
    #{
        schema => 1,
        inputs => #{optimized_ir => digest(Ir), rtl => digest(Rtl)},
        nodes => Index,
        order => [maps:get(name, N) || N <- Nodes],
        bindings => Bindings,
        registers => BoundRegisters,
        signals => input_signals(Inputs)
    };
plan(_, _, _) ->
    error(spacetime_dependency_input_limit).

-doc "Returns passive scalar input taps proven to match the received XLS tuple's RTL slices. Merge these by exact signal identity with existing taps; no intermediate selector probes are required.".
-spec signals(plan()) -> [xls_protocol_spacetime:signal()].
signals(#{signals := Signals}) -> Signals.

-doc "Returns original register metadata augmented with checked IR state/update bindings. Unknown bindings must remain unresolved in the capture graph.".
-spec registers(plan()) -> [register()].
registers(#{registers := Registers}) -> Registers.

-doc "Evaluates the scalar graph in its retained topological order once for a clock, using observed unsigned values keyed by exact RTL signal. Missing leaves and unsupported nodes yield unknown. Rejects out-of-width observations. Selection evaluates only its chosen value, even when another branch is unknown.".
-spec sample(plan(), #{binary() => non_neg_integer()}) -> sample().
sample(#{nodes := Nodes, order := Order, bindings := Bindings}, Observed) ->
    Values = lists:foldl(
        fun(Name, Acc) ->
            Node = maps:get(Name, Nodes),
            Value =
                case maps:find(Name, Bindings) of
                    {ok, #{signal := Signal, width := Width}} -> observed(Signal, Width, Observed);
                    error -> evaluate(Node, Nodes, Acc)
                end,
            Acc#{Name => Value}
        end,
        #{},
        Order
    ),
    #{values => Values}.

-doc "Resolves exactly one selected next_value of an emitted register. The caller must compare a known returned value with the independently observed enabled D before publishing lineage. No selected update, overlapping predicates or unknown predicates remain explicit unknown results. Reads must bind masks to the pre-edge source versions, not versions installed by earlier iteration over this clock's writes.".
-spec write(plan(), binary(), sample()) -> result().
write(Plan = #{registers := Registers}, Name, Sample = #{values := Values}) ->
    case [R || R = #{name := N} <- Registers, N =:= Name] of
        [#{binding_status := supported, updates := Updates, width := Width}] ->
            Predicates = [{U, predicate_value(maps:get(predicate, U), Values)} || U <- Updates],
            case
                {
                    [U || {U, V} <- Predicates, V =:= 1],
                    lists:any(fun({_, V}) -> V =:= unknown end, Predicates)
                }
            of
                {[#{node := Id, value := Value}], false} ->
                    W0 = lists:foldl(
                        fun({#{predicate := Predicate}, _}, Acc) ->
                            walk_predicate(Predicate, Plan, Sample, Acc)
                        end,
                        empty_walk(),
                        Predicates
                    ),
                    W1 = walk(Value, mask(Width), data, Plan, Sample, 0, W0),
                    finish(maps:get(Value, Values, unknown), [Id], W1);
                {Selected, Unknown} ->
                    unknown_result({unresolved_next_value, Name, length(Selected), Unknown})
            end;
        [_] ->
            unknown_result({unbound_register, Name});
        [] ->
            unknown_result({unknown_register, Name})
    end.

-doc "Returns selected operational inputs of a scalar IR node for the requested nonzero output-bit mask. Bit slices/concats preserve exact bit positions; arithmetic retains structurally required operand ranges, and selectors retain control inputs plus only selected data alternatives. Unsupported operations and absent values become explicit unknown roots. Rejects invalid output masks or unknown node identity.".
-spec read(plan(), binary(), non_neg_integer(), sample()) -> result().
read(Plan = #{nodes := Nodes}, Name, Mask, Sample = #{values := Values}) ->
    #{width := Width} = maps:get(Name, Nodes),
    true = Mask > 0 andalso Mask =< mask(Width),
    finish(
        maps:get(Name, Values, unknown), [], walk(Name, Mask, data, Plan, Sample, 0, empty_walk())
    ).

%% Hash exact source bytes without retaining another large copy in the plan.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

%% Bounded line recognizers only identify declarations; operand syntax is split structurally.
-spec captures(binary(), binary(), [non_neg_integer()]) -> [[binary()]].
captures(Text, Pattern, Groups) ->
    case re:run(Text, Pattern, [global, {capture, Groups, binary}]) of
        {match, Rows} -> Rows;
        nomatch -> []
    end.

%% Parse a scalar declaration while retaining binary op/attribute names, avoiding atom creation.
-spec parse_node(binary(), binary(), binary(), binary()) -> scalar_node().
parse_node(Name, WidthText, Op, Body) ->
    Width = binary_to_integer(WidthText),
    true = Width > 0 andalso Width =< ?MAX_WIDTH,
    {Args, Attrs} = arguments(Body),
    #{name => Name, width => Width, op => Op, args => Args, attrs => Attrs}.

%% Normalize immutable syntax once; no literal, selector-list or attribute parsing occurs per clock.
-spec normalize_node(scalar_node(), #{binary() => scalar_node()}) -> scalar_node().
normalize_node(N = #{op := Op, args := Args, attrs := Attrs, width := Width}, Nodes) ->
    Mask = mask(Width),
    Prepared = N#{
        bit_mask => Mask,
        arg_widths => [maps:get(width, maps:get(A, Nodes, #{width => 1})) || A <- Args]
    },
    case Op of
        <<"literal">> ->
            Prepared#{literal_value => parse_integer(maps:get(<<"value">>, Attrs)) band Mask};
        <<"bit_slice">> ->
            Prepared#{slice_start => int_attr(<<"start">>, Attrs)};
        _ when Op =:= <<"sel">>; Op =:= <<"priority_sel">>; Op =:= <<"one_hot_sel">> ->
            Prepared#{
                choices => list_items(maps:get(<<"cases">>, Attrs)),
                default_case => maps:get(<<"default">>, Attrs, none)
            };
        _ ->
            Prepared
    end.

%% Admit only literal one-dimensional bit arrays, with cumulative entry and bit limits.
-spec parse_tables([binary()]) -> #{binary() => table()}.
parse_tables(Lines) ->
    {Tables, _, _} = lists:foldl(
        fun(Line, {Acc, Entries, Bits}) ->
            case
                captures(
                    Line,
                    <<"^  ([A-Za-z_][A-Za-z_0-9.]*): bits\\[([0-9]+)\\]\\[([0-9]+)\\] = literal\\((.*)\\)$">>,
                    [1, 2, 3, 4]
                )
            of
                [[Name, WidthText, CountText, Body]] ->
                    Width = binary_to_integer(WidthText),
                    Count = binary_to_integer(CountText),
                    true = Width > 0 andalso Width =< ?MAX_WIDTH andalso Count > 0,
                    true = Entries + Count =< ?MAX_TABLE_ENTRIES,
                    true = Bits + Width * Count =< ?MAX_TABLE_BITS,
                    {[], Attrs} = arguments(Body),
                    Values = [parse_integer(V) || V <- list_items(maps:get(<<"value">>, Attrs))],
                    true = length(Values) =:= Count,
                    true = lists:all(fun(V) -> V >= 0 andalso V =< mask(Width) end, Values),
                    false = maps:is_key(Name, Acc),
                    {
                        Acc#{
                            Name => #{
                                width => Width, count => Count, values => list_to_tuple(Values)
                            }
                        },
                        Entries + Count,
                        Bits + Width * Count
                    };
                [] ->
                    {Acc, Entries, Bits}
            end
        end,
        {#{}, 0, 0},
        Lines
    ),
    Tables.

%% A table read has one explicit scalar index and exactly matching element/result width.
%% XLS IrInterpreter::HandleArrayIndex clamps each index to the final array entry.
-spec bind_table(scalar_node(), #{binary() => table()}) -> scalar_node().
bind_table(N = #{op := <<"array_index">>, args := [Array], attrs := Attrs, width := W}, Tables) ->
    case {maps:find(Array, Tables), list_items(maps:get(<<"indices">>, Attrs, <<"[]">>))} of
        {{ok, Table = #{width := W}}, [Index]} -> N#{table => Table, index => Index};
        _ -> N
    end;
bind_table(N, _) ->
    N.

%% Reject duplicate identities before constructing a lookup table.
-spec unique_nodes([scalar_node()]) -> #{binary() => scalar_node()}.
unique_nodes(Nodes) ->
    lists:foldl(
        fun(N = #{name := Name}, Acc) ->
            false = maps:is_key(Name, Acc),
            Acc#{Name => N}
        end,
        #{},
        Nodes
    ).

%% Delimiter-aware splitting keeps cases and source-position tuples intact.
-spec split(binary()) -> [binary()].
split(Bytes) -> split(binary_to_list(Bytes), 0, [], []).

%% Track nested tuple/list depth; malformed closing delimiters fail rather than flatten.
-spec split(string(), non_neg_integer(), string(), [binary()]) -> [binary()].
split([], 0, Current, Acc) ->
    lists:reverse([trim(list_to_binary(lists:reverse(Current))) | Acc]);
split([C | Rest], Depth, Current, Acc) when C =:= $[; C =:= $( ->
    split(Rest, Depth + 1, [C | Current], Acc);
split([C | Rest], Depth, Current, Acc) when (C =:= $] orelse C =:= $)), Depth > 0 ->
    split(Rest, Depth - 1, [C | Current], Acc);
split([C | _], 0, _, _) when C =:= $]; C =:= $) -> error(unbalanced_dependency_arguments);
split([$, | Rest], 0, Current, Acc) ->
    split(Rest, 0, [], [trim(list_to_binary(lists:reverse(Current))) | Acc]);
split([C | Rest], Depth, Current, Acc) ->
    split(Rest, Depth, [C | Current], Acc).

%% Strip surrounding whitespace without modifying symbol spelling.
-spec trim(binary()) -> binary().
trim(B) -> string:trim(B).

%% Separate positional symbols from key/value attributes, rejecting duplicates.
-spec arguments(binary()) -> {[binary()], #{binary() => binary()}}.
arguments(Body) ->
    {Rev, Attrs} = lists:foldl(
        fun(Token, {Args, Fields}) ->
            case binary:split(Token, <<"=">>) of
                [<<>>] ->
                    {Args, Fields};
                [Arg] ->
                    {[trim(Arg) | Args], Fields};
                [Key, Value] ->
                    K = trim(Key),
                    false = maps:is_key(K, Fields),
                    {Args, Fields#{K => trim(Value)}}
            end
        end,
        {[], #{}},
        split(Body)
    ),
    {lists:reverse(Rev), Attrs}.

%% Generated XLS state-read symbols gain exactly the emitter's two-underscore prefix.
%% Both the supplied observed register and exact RTL declaration must agree in width.
-spec state_bindings([scalar_node()], [register()], binary()) -> #{binary() => binding()}.
state_bindings(Nodes, Registers, Rtl) ->
    ByName = maps:from_list([{maps:get(name, R), R} || R <- Registers]),
    lists:foldl(
        fun(#{name := Node, width := W, op := Op, attrs := A}, Acc) ->
            case Op of
                <<"state_read">> ->
                    State = maps:get(<<"state_element">>, A),
                    Name = <<"__", State/binary>>,
                    case maps:find(Name, ByName) of
                        {ok, #{width := W}} ->
                            case declared(Rtl, Name, W, <<"reg">>) of
                                true ->
                                    Acc#{
                                        Node => #{
                                            kind => state,
                                            signal => Name,
                                            width => W,
                                            state_element => State
                                        }
                                    };
                                false ->
                                    Acc
                            end;
                        _ ->
                            Acc
                    end;
                _ ->
                    Acc
            end
        end,
        #{},
        Nodes
    ).

%% Scalar initial values belong to one proc's common transition boundary. Other
%% proc counts or aggregate initial forms provide no recurrence-alias evidence.
-spec initial_state([binary()]) -> #{binary() => {pos_integer(), non_neg_integer()}}.
initial_state(Lines) ->
    Headers = [L || L <- Lines, re:run(L, <<"^(top )?proc ">>, [{capture, none}]) =:= match],
    case Headers of
        [Header] ->
            case
                captures(
                    Header,
                    <<"^(?:top )?proc [A-Za-z_][A-Za-z_0-9]*(?:<.*>)?\\((.*), init=\\{([^{}]*)\\}\\) \\{$">>,
                    [1, 2]
                )
            of
                [[Parameters, Initial]] -> scalar_initials(Parameters, Initial);
                [] -> #{}
            end;
        _ ->
            #{}
    end.

%% Only a complete scalar parameter/initial list can establish initial equality;
%% unsupported syntax is left unbound rather than guessing zero or source offsets.
-spec scalar_initials(binary(), binary()) -> #{binary() => {pos_integer(), non_neg_integer()}}.
scalar_initials(Parameters, Initial) ->
    Pattern = <<"([A-Za-z_][A-Za-z_0-9]*): bits\\[([0-9]+)\\](?: pos=\\[[^\\]]*\\])?">>,
    case re:run(Parameters, Pattern, [global, {capture, [1, 2], binary}]) of
        {match, Declarations} ->
            Remainder = re:replace(Parameters, Pattern, <<>>, [global, {return, binary}]),
            Tokens = [trim(V) || V <- binary:split(Initial, <<",">>, [global])],
            Complete = re:run(Remainder, <<"^[ ,]*$">>, [{capture, none}]) =:= match,
            Literals = lists:all(
                fun(T) ->
                    re:run(T, <<"^(0x[0-9A-Fa-f][0-9A-Fa-f_]*|0b[01][01_]*|[0-9][0-9_]*)$">>, [
                        {capture, none}
                    ]) =:= match
                end,
                Tokens
            ),
            case Complete andalso Literals andalso length(Declarations) =:= length(Tokens) of
                true ->
                    Rows = [
                        {Name, {binary_to_integer(Width), parse_integer(Value)}}
                     || {[Name, Width], Value} <- lists:zip(Declarations, Tokens)
                    ],
                    case
                        length(lists:usort([N || {N, _} <- Rows])) =:= length(Rows) andalso
                            lists:all(
                                fun({_, {W, V}}) ->
                                    W > 0 andalso W =< ?MAX_WIDTH andalso V =< mask(W)
                                end,
                                Rows
                            )
                    of
                        true -> maps:from_list(Rows);
                        false -> #{}
                    end;
                false ->
                    #{}
            end;
        nomatch ->
            #{}
    end.

%% Equal initial constants and the same sole guard/value preserve equality on
%% every shared proc transition (including holds). This is an IR recurrence
%% argument, not equality inferred from sampled values or a native proof. More
%% than one update is excluded because its conflict semantics need separate work.
-spec equivalent_states(
    [scalar_node()],
    #{binary() => binding()},
    #{binary() => [update()]},
    #{binary() => {pos_integer(), non_neg_integer()}}
) ->
    #{binary() => binding()}.
equivalent_states(Nodes, Direct, Updates, Initial) ->
    Groups = lists:foldl(
        fun
            (#{name := Name, op := <<"state_read">>, width := W, attrs := A}, Acc) ->
                State = maps:get(<<"state_element">>, A),
                case {maps:find(State, Initial), maps:get(State, Updates, [])} of
                    {{ok, {W, Value}}, [#{value := Next, predicate := Predicate}]} ->
                        Key = {W, Value, Next, Predicate},
                        maps:update_with(
                            Key, fun(Group) -> [{Name, State} | Group] end, [{Name, State}], Acc
                        );
                    _ ->
                        Acc
                end;
            (_, Acc) ->
                Acc
        end,
        #{},
        Nodes
    ),
    maps:fold(
        fun(_, Group, Acc) ->
            Representatives = lists:usort([
                {maps:get(signal, B), maps:get(state_element, B)}
             || {Name, _} <- Group, {ok, B} <- [maps:find(Name, Direct)]
            ]),
            case Representatives of
                [{Signal, State}] ->
                    [Binding | _] = [
                        B
                     || {_, B = #{signal := S, state_element := E}} <- maps:to_list(Direct),
                        S =:= Signal,
                        E =:= State
                    ],
                    lists:foldl(
                        fun({Name, Equivalent}, Bindings) ->
                            case maps:is_key(Name, Bindings) of
                                true ->
                                    Bindings;
                                false ->
                                    Bindings#{
                                        Name => Binding#{
                                            state_element := Equivalent, equivalent_state => State
                                        }
                                    }
                            end
                        end,
                        Acc,
                        Group
                    );
                _ ->
                    Acc
            end
        end,
        Direct,
        Groups
    ).

%% Check exact generated scalar declarations, including one-bit syntax.
-spec declared(binary(), binary(), pos_integer(), binary()) -> boolean().
declared(Rtl, Name, Width, Kind) ->
    Prefix =
        case Width of
            1 -> <<>>;
            _ -> <<"[", (integer_to_binary(Width - 1))/binary, ":0] ">>
        end,
    Expected = <<"  ", Kind/binary, " ", Prefix/binary, Name/binary, ";">>,
    lists:member(Expected, binary:split(Rtl, <<"\n">>, [global])).

%% Bind scalar fields of a direct receive payload only after checking packed RTL slices.
-spec input_bindings([scalar_node()], [binary()], binary()) -> #{binary() => binding()}.
input_bindings(Nodes, Lines, Rtl) ->
    Receives = maps:from_list([
        {Name, Channel}
     || Line <- Lines,
        [Name, Channel] <- captures(
            Line,
            <<"^  ([A-Za-z_][A-Za-z_0-9.]*): .* = receive\\(.*channel=([A-Za-z_][A-Za-z_0-9]*),.*\\)$">>,
            [1, 2]
        )
    ]),
    Tuples = maps:from_list([
        {Name, {Receive, tuple_widths(Types)}}
     || Line <- Lines,
        [Name, Types, Receive] <- captures(
            Line,
            <<"^  ([A-Za-z_][A-Za-z_0-9]*): \\((bits\\[[0-9]+\\](?:, bits\\[[0-9]+\\])*)\\) = tuple_index\\(([A-Za-z_][A-Za-z_0-9.]*), index=1,.*\\)$">>,
            [1, 2, 3]
        )
    ]),
    lists:foldl(
        fun(#{name := Name, width := W, op := Op, args := Args, attrs := Attrs}, Acc) ->
            case {Op, Args} of
                {<<"tuple_index">>, [Tuple]} ->
                    case maps:find(Tuple, Tuples) of
                        {ok, {Receive, Widths}} ->
                            Index = int_attr(<<"index">>, Attrs),
                            case maps:find(Receive, Receives) of
                                {ok, Channel} when Index < length(Widths) ->
                                    W = lists:nth(Index + 1, Widths),
                                    Low = lists:sum(lists:nthtail(Index + 1, Widths)),
                                    High = Low + W - 1,
                                    Expected =
                                        <<"  assign ", Name/binary, " = ", Channel/binary, "[",
                                            (integer_to_binary(High))/binary, ":",
                                            (integer_to_binary(Low))/binary, "];">>,
                                    case
                                        declared(Rtl, Name, W, <<"wire">>) andalso
                                            lists:member(
                                                Expected, binary:split(Rtl, <<"\n">>, [global])
                                            )
                                    of
                                        true ->
                                            Acc#{
                                                Name => #{kind => input, signal => Name, width => W}
                                            };
                                        false ->
                                            Acc
                                    end;
                                _ ->
                                    Acc
                            end;
                        error ->
                            Acc
                    end;
                _ ->
                    Acc
            end
        end,
        #{},
        Nodes
    ).

%% Parse flat scalar tuple widths without accepting nested or non-bit payloads.
-spec tuple_widths(binary()) -> [pos_integer()].
tuple_widths(Text) ->
    [binary_to_integer(W) || [W] <- captures(Text, <<"bits\\[([0-9]+)\\]">>, [1])].

%% Keep next-value records separate from scalar expressions and preserve guard identity.
-spec parse_updates([binary()]) -> #{binary() => [update()]}.
parse_updates(Lines) ->
    lists:foldl(
        fun(Line, Acc) ->
            case
                captures(Line, <<"^  ([A-Za-z_][A-Za-z_0-9.]*): \\(\\) = next_value\\((.*)\\)$">>, [
                    1, 2
                ])
            of
                [[Name, Body]] ->
                    {[], Attrs} = arguments(Body),
                    State = maps:get(<<"state_element">>, Attrs),
                    U = #{
                        node => Name,
                        value => maps:get(<<"value">>, Attrs),
                        predicate => maps:get(<<"predicate">>, Attrs, unconditional)
                    },
                    Acc#{State => maps:get(State, Acc, []) ++ [U]};
                [] ->
                    Acc
            end
        end,
        #{},
        Lines
    ).

%% Register target association follows the checked state binding, never data-value equality.
-spec bind_register(register(), #{binary() => binding()}, #{binary() => [update()]}) -> register().
bind_register(R = #{name := Name}, Bindings, Updates) ->
    case
        [
            State
         || {_, #{kind := state, signal := Signal, state_element := State}} <- maps:to_list(
                Bindings
            ),
            Signal =:= Name
        ]
    of
        [State] ->
            R#{
                ir_state => State,
                updates => maps:get(State, Updates, []),
                binding_status => supported
            };
        _ ->
            R#{updates => [], binding_status => unknown}
    end.

%% Extra input taps use a dedicated semantic namespace; exact paths are ordinary passive probes.
-spec input_signals(#{binary() => binding()}) -> [xls_protocol_spacetime:signal()].
input_signals(Bindings) ->
    [
        #{
            id => <<"signal/", Name/binary>>,
            name => Name,
            path => <<"TOP.protocol_application_top.network.core.", Name/binary>>,
            width => W,
            actor => null,
            meaning => <<"dependency_input">>,
            evidence => <<"Scalar received tuple field and exact RTL packed slice agree">>
        }
     || {_, #{kind := input, signal := Name, width := W}} <- lists:sort(maps:to_list(Bindings))
    ].

%% Observed values cannot silently truncate to the declared signal width.
-spec observed(binary(), pos_integer(), #{binary() => non_neg_integer()}) ->
    non_neg_integer() | unknown.
observed(Signal, Width, Values) ->
    case maps:find(Signal, Values) of
        {ok, V} when is_integer(V), V >= 0, V < (1 bsl Width) -> V;
        {ok, V} -> error({spacetime_dependency_value, Signal, Width, V});
        error -> unknown
    end.

%% Scalar evaluation is deterministic and bounded by the already checked node/width limits.
-spec evaluate(scalar_node(), #{binary() => scalar_node()}, #{
    binary() => non_neg_integer() | unknown
}) ->
    non_neg_integer() | unknown.
evaluate(#{op := <<"literal">>, literal_value := Value}, _, _) ->
    Value;
evaluate(#{op := <<"bit_slice">>, args := [A], slice_start := Start, bit_mask := Mask}, _, Values) ->
    case maps:get(A, Values, unknown) of
        unknown -> unknown;
        V -> (V bsr Start) band Mask
    end;
evaluate(
    #{op := <<"array_index">>, table := #{count := Count, values := Entries}, index := Index},
    _,
    Values
) ->
    case maps:get(Index, Values, unknown) of
        unknown -> unknown;
        V -> element(min(V, Count - 1) + 1, Entries)
    end;
evaluate(N = #{op := Op, args := [_], width := W}, _Nodes, Values) when
    Op =:= <<"sel">>; Op =:= <<"priority_sel">>; Op =:= <<"one_hot_sel">>
->
    case selected(N, Values) of
        {ok, Names} ->
            case operand_values(Names, Values) of
                unknown -> unknown;
                Vs -> lists:foldl(fun(V, Acc) -> V bor Acc end, 0, Vs) band mask(W)
            end;
        unknown ->
            unknown
    end;
evaluate(#{op := Op, args := Args, arg_widths := Widths, attrs := A, width := W}, _, Values) ->
    case operand_values(Args, Values) of
        unknown ->
            unknown;
        Vs ->
            scalar(Op, Vs, Widths, A, W)
    end.

%% Lookups return unknown for unsupported tuple/channel operands and missing scalar values.
-spec operand_values([binary()], #{binary() => non_neg_integer() | unknown}) ->
    [non_neg_integer()] | unknown.
operand_values(Names, Values) ->
    Vs = [maps:get(N, Values, unknown) || N <- Names],
    case lists:member(unknown, Vs) of
        true -> unknown;
        false -> Vs
    end.

%% Integer literals preserve XLS's underscores and hexadecimal/binary notation.
-spec parse_integer(binary()) -> integer().
parse_integer(Text) ->
    Clean = binary:replace(Text, <<"_">>, <<>>, [global]),
    case Clean of
        <<"0x", Hex/binary>> -> binary_to_integer(Hex, 16);
        <<"0b", Bits/binary>> -> binary_to_integer(Bits, 2);
        _ -> binary_to_integer(Clean)
    end.

%% Scalar attributes are finite nonnegative decimal values in the supported XLS subset.
-spec int_attr(binary(), #{binary() => binary()}) -> non_neg_integer().
int_attr(Key, A) ->
    N = binary_to_integer(maps:get(Key, A)),
    true = N >= 0,
    N.

%% Width-bounded mask shared by evaluation and dependency projection.
-spec mask(non_neg_integer()) -> non_neg_integer().
mask(W) -> (1 bsl W) - 1.

%% Interpret supported operations exactly; unknown op forms remain explicit opaque values.
-spec scalar(
    binary(), [non_neg_integer()], [pos_integer()], #{binary() => binary()}, pos_integer()
) -> non_neg_integer() | unknown.
scalar(<<"bit_slice">>, [V], _, A, W) ->
    (V bsr int_attr(<<"start">>, A)) band mask(W);
scalar(<<"concat">>, Vs, Widths, _, _) ->
    lists:foldl(fun({V, W}, Acc) -> (Acc bsl W) bor V end, 0, lists:zip(Vs, Widths));
scalar(<<"not">>, [V], _, _, W) ->
    (bnot V) band mask(W);
scalar(<<"and">>, Vs, _, _, W) ->
    lists:foldl(fun(A, B) -> A band B end, mask(W), Vs);
scalar(<<"or">>, Vs, _, _, _) ->
    lists:foldl(fun(A, B) -> A bor B end, 0, Vs);
scalar(<<"xor">>, Vs, _, _, _) ->
    lists:foldl(fun(A, B) -> A bxor B end, 0, Vs);
scalar(<<"nand">>, Vs, Widths, A, W) ->
    (bnot scalar(<<"and">>, Vs, Widths, A, W)) band mask(W);
scalar(<<"nor">>, Vs, Widths, A, W) ->
    (bnot scalar(<<"or">>, Vs, Widths, A, W)) band mask(W);
scalar(<<"add">>, [A, B], _, _, W) ->
    (A + B) band mask(W);
scalar(<<"sub">>, [A, B], _, _, W) ->
    (A - B) band mask(W);
scalar(<<"umul">>, [A, B], _, _, W) ->
    (A * B) band mask(W);
scalar(<<"smul">>, [A, B], [AW, BW], _, W) ->
    (signed(A, AW) * signed(B, BW)) band mask(W);
scalar(<<"eq">>, [A, B], _, _, _) ->
    boolean(A =:= B);
scalar(<<"ne">>, [A, B], _, _, _) ->
    boolean(A =/= B);
scalar(<<"ult">>, [A, B], _, _, _) ->
    boolean(A < B);
scalar(<<"ule">>, [A, B], _, _, _) ->
    boolean(A =< B);
scalar(<<"ugt">>, [A, B], _, _, _) ->
    boolean(A > B);
scalar(<<"uge">>, [A, B], _, _, _) ->
    boolean(A >= B);
scalar(<<"slt">>, [A, B], [AW, BW], _, _) ->
    boolean(signed(A, AW) < signed(B, BW));
scalar(<<"sle">>, [A, B], [AW, BW], _, _) ->
    boolean(signed(A, AW) =< signed(B, BW));
scalar(<<"sgt">>, [A, B], [AW, BW], _, _) ->
    boolean(signed(A, AW) > signed(B, BW));
scalar(<<"sge">>, [A, B], [AW, BW], _, _) ->
    boolean(signed(A, AW) >= signed(B, BW));
scalar(<<"or_reduce">>, [A], _, _, _) ->
    boolean(A =/= 0);
scalar(<<"and_reduce">>, [A], [W], _, _) ->
    boolean(A =:= mask(W));
scalar(<<"xor_reduce">>, [A], _, _, _) ->
    parity(A, 0);
scalar(<<"reverse">>, [A], [W], _, _) ->
    reverse_bits(A, W, 0);
scalar(<<"zero_ext">>, [A], _, _, _) ->
    A;
scalar(<<"sign_ext">>, [A], [IW], _, W) ->
    signed(A, IW) band mask(W);
scalar(<<"decode">>, [A], _, _, W) when A < W -> 1 bsl A;
scalar(<<"decode">>, [_], _, _, _) ->
    0;
scalar(<<"one_hot">>, [A], [IW], Attrs, _) ->
    one_hot(A, IW, maps:get(<<"lsb_prio">>, Attrs, <<"true">>));
scalar(_, _, _, _, _) ->
    unknown.

%% Two's-complement interpretation is local to signed operations.
-spec signed(non_neg_integer(), pos_integer()) -> integer().
signed(V, W) ->
    case V band (1 bsl (W - 1)) of
        0 -> V;
        _ -> V - (1 bsl W)
    end.

%% Boolean result occupies one scalar bit.
-spec boolean(boolean()) -> 0 | 1.
boolean(true) -> 1;
boolean(false) -> 0.

%% Reverse a bounded scalar without strings or host-width truncation.
-spec reverse_bits(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
reverse_bits(_, 0, Acc) -> Acc;
reverse_bits(V, N, Acc) -> reverse_bits(V bsr 1, N - 1, (Acc bsl 1) bor (V band 1)).

%% Count set bits modulo two without treating the numerical LSB as parity.
-spec parity(non_neg_integer(), 0 | 1) -> 0 | 1.
parity(0, Acc) -> Acc;
parity(V, Acc) -> parity(V bsr 1, Acc bxor (V band 1)).

%% XLS one_hot selects the declared priority direction and adds a zero-input bit.
-spec one_hot(non_neg_integer(), pos_integer(), binary()) -> non_neg_integer() | unknown.
one_hot(0, W, _) -> 1 bsl W;
one_hot(V, _, <<"true">>) -> V band (-V);
one_hot(V, W, <<"false">>) -> 1 bsl (W - 1 - high_zeroes(V, W));
one_hot(_, _, _) -> unknown.

%% Count leading zeroes within a known nonzero scalar width.
-spec high_zeroes(non_neg_integer(), pos_integer()) -> non_neg_integer().
high_zeroes(V, W) ->
    case V band (1 bsl (W - 1)) of
        0 -> 1 + high_zeroes(V, W - 1);
        _ -> 0
    end.

%% Flat bracketed attributes retain each token's syntax; nested tables are never admitted.
-spec list_items(binary()) -> [binary()].
list_items(<<"[]">>) ->
    [];
list_items(<<"[", Rest/binary>>) ->
    N = byte_size(Rest) - 1,
    <<Body:N/binary, "]">> = Rest,
    split(Body).

%% Choose data alternatives solely from a known runtime selector; all chosen one-hot cases count.
-spec selected(scalar_node(), #{binary() => non_neg_integer() | unknown}) ->
    {ok, [binary()]} | unknown.
selected(#{op := Op, args := [Selector], choices := Choices, default_case := Default}, Values) ->
    case maps:get(Selector, Values, unknown) of
        unknown ->
            unknown;
        V when Op =:= <<"sel">> ->
            case V < length(Choices) of
                true -> {ok, [lists:nth(V + 1, Choices)]};
                false -> default_case(Default)
            end;
        V when Op =/= <<"sel">>, V >= (1 bsl length(Choices)) -> unknown;
        V when Op =:= <<"one_hot_sel">> ->
            {ok, [N || {I, N} <- lists:enumerate(0, Choices), V band (1 bsl I) =/= 0]};
        0 ->
            default_case(Default);
        V ->
            [{Chosen, _} | _] = [
                {N, I}
             || {I, N} <- lists:enumerate(0, Choices), V band (1 bsl I) =/= 0
            ],
            {ok, [Chosen]}
    end.

%% Missing defaults are unknown, never an invented zero branch.
-spec default_case(binary() | none) -> {ok, [binary()]} | unknown.
default_case(none) -> unknown;
default_case(Name) -> {ok, [Name]}.

%% State update predicates are one-bit expressions or explicit unconditional updates.
-spec predicate_value(binary() | unconditional, #{binary() => non_neg_integer() | unknown}) ->
    non_neg_integer() | unknown.
predicate_value(unconditional, _) -> 1;
predicate_value(Name, Values) -> maps:get(Name, Values, unknown).

%% Empty dependency accumulator is bounded independently for each requested output.
-spec empty_walk() -> walk().
empty_walk() -> #{data_masks => #{}, control_masks => #{}, unknown => [], seen => #{}, visits => 0}.

%% State update selectors remain control dependencies even when their selected value is constant.
-spec walk_predicate(binary() | unconditional, plan(), sample(), walk()) -> walk().
walk_predicate(unconditional, _, _, W) -> W;
walk_predicate(Name, P, S, W) -> walk(Name, 1, control, P, S, 0, W).

%% Clamp masks at each scalar boundary; depth and total visits bound expansion.
-spec walk(
    binary(), non_neg_integer(), data | control, plan(), sample(), non_neg_integer(), walk()
) -> walk().
walk(Name, Requested, Role, P = #{nodes := Nodes}, S, Depth, W) ->
    Mask =
        case maps:find(Name, Nodes) of
            {ok, #{bit_mask := Limit}} -> Requested band Limit;
            error -> Requested
        end,
    case Mask of
        0 -> W;
        _ -> walk_bits(Name, Mask, Role, P, S, Depth, W)
    end.

%% Traverse only newly requested bits per node/role within this one target query.
-spec walk_bits(
    binary(), non_neg_integer(), data | control, plan(), sample(), non_neg_integer(), walk()
) -> walk().
walk_bits(
    Name,
    Requested,
    Role,
    P = #{nodes := Nodes, bindings := Bindings},
    S = #{values := Values},
    Depth,
    W = #{seen := Seen, visits := Count}
) ->
    Key = {Name, Role},
    Previous = maps:get(Key, Seen, 0),
    Mask = Requested band (bnot Previous),
    case Mask of
        0 ->
            W;
        _ when Depth >= ?MAX_DEPTH; Count >= ?MAX_VISITS ->
            add_unknown({dependency_limit, Name}, W);
        _ ->
            W1 = W#{seen := Seen#{Key => Previous bor Mask}, visits := Count + 1},
            case maps:find(Name, Bindings) of
                {ok, #{kind := state, signal := Signal, width := Width}} ->
                    W2 = add_mask(Role, Signal, Mask band mask(Width), W1),
                    case maps:get(Name, Values, unknown) of
                        unknown -> add_unknown({missing_value, Signal}, W2);
                        _ -> W2
                    end;
                {ok, #{kind := input, signal := Signal}} ->
                    add_unknown({external_input, Signal, Mask, Role}, W1);
                error ->
                    case maps:find(Name, Nodes) of
                        {ok, N} -> walk_node(N, Mask, Role, P, S, Depth + 1, W1);
                        error -> add_unknown({missing_node, Name}, W1)
                    end
            end
    end.

%% Transfer output bit positions structurally; dynamic alternatives require known selectors.
-spec walk_node(
    scalar_node(), non_neg_integer(), data | control, plan(), sample(), non_neg_integer(), walk()
) -> walk().
walk_node(#{op := <<"literal">>}, _, _, _, _, _, W) ->
    W;
walk_node(
    #{op := <<"array_index">>, table := _, index := Index, name := Name},
    _,
    _,
    P,
    S = #{values := Values},
    D,
    W
) ->
    W1 = walk_all([Index], control, P, S, D, W),
    case maps:get(Index, Values, unknown) of
        unknown -> add_unknown({unknown_table_index, Name, Index}, W1);
        _ -> W1
    end;
walk_node(#{op := <<"bit_slice">>, args := [A], slice_start := Start}, M, R, P, S, D, W) ->
    walk(A, M bsl Start, R, P, S, D, W);
walk_node(#{op := <<"concat">>, args := Args}, M, R, P, S, D, W) ->
    walk_concat(lists:reverse(Args), M, 0, R, P, S, D, W);
walk_node(N = #{op := Op, args := [Selector]}, M, R, P, S = #{values := Values}, D, W) when
    Op =:= <<"sel">>; Op =:= <<"priority_sel">>; Op =:= <<"one_hot_sel">>
->
    W1 = walk_all([Selector], control, P, S, D, W),
    case selected(N, Values) of
        {ok, Names} -> lists:foldl(fun(Name, Acc) -> walk(Name, M, R, P, S, D, Acc) end, W1, Names);
        unknown -> add_unknown({unknown_selector, maps:get(name, N), Selector}, W1)
    end;
walk_node(#{op := <<"reverse">>, args := [A]}, M, R, P = #{nodes := Nodes}, S, D, W) ->
    IW = maps:get(width, maps:get(A, Nodes)),
    walk(A, reverse_bits(M, IW, 0), R, P, S, D, W);
walk_node(#{op := Op, args := [A]}, M, R, P = #{nodes := Nodes}, S, D, W) when
    Op =:= <<"zero_ext">>; Op =:= <<"sign_ext">>
->
    IW = maps:get(width, maps:get(A, Nodes)),
    Low = M band mask(IW),
    Extra =
        case Op =:= <<"sign_ext">> andalso (M bsr IW) =/= 0 of
            true -> 1 bsl (IW - 1);
            false -> 0
        end,
    walk(A, Low bor Extra, R, P, S, D, W);
walk_node(#{op := Op, args := Args}, M, R, P, S, D, W) when
    Op =:= <<"and">>;
    Op =:= <<"or">>;
    Op =:= <<"xor">>;
    Op =:= <<"nand">>;
    Op =:= <<"nor">>;
    Op =:= <<"not">>
->
    lists:foldl(fun(A, Acc) -> walk(A, M, R, P, S, D, Acc) end, W, Args);
walk_node(#{op := Op, args := Args}, M, R, P, S, D, W) when
    Op =:= <<"add">>; Op =:= <<"sub">>; Op =:= <<"umul">>
->
    Prefix = mask(highest_bit(M) + 1),
    lists:foldl(fun(A, Acc) -> walk(A, Prefix, R, P, S, D, Acc) end, W, Args);
walk_node(#{op := Op, args := Args}, _, R, P, S, D, W) when
    Op =:= <<"smul">>;
    Op =:= <<"eq">>;
    Op =:= <<"ne">>;
    Op =:= <<"ult">>;
    Op =:= <<"ule">>;
    Op =:= <<"ugt">>;
    Op =:= <<"uge">>;
    Op =:= <<"slt">>;
    Op =:= <<"sle">>;
    Op =:= <<"sgt">>;
    Op =:= <<"sge">>;
    Op =:= <<"and_reduce">>;
    Op =:= <<"or_reduce">>;
    Op =:= <<"xor_reduce">>;
    Op =:= <<"decode">>;
    Op =:= <<"one_hot">>
->
    walk_all(Args, R, P, S, D, W);
walk_node(#{name := Name, op := Op}, _, _, _, _, _, W) ->
    add_unknown({unsupported_node, Name, Op}, W).

%% Concatenation operands are most-significant first; traverse reversed from bit zero.
-spec walk_concat(
    [binary()],
    non_neg_integer(),
    non_neg_integer(),
    data | control,
    plan(),
    sample(),
    non_neg_integer(),
    walk()
) -> walk().
walk_concat([], _, _, _, _, _, _, W) ->
    W;
walk_concat([A | Rest], M, Offset, R, P = #{nodes := Nodes}, S, D, W) ->
    case maps:find(A, Nodes) of
        {ok, #{width := Width}} ->
            W1 = walk(A, (M bsr Offset) band mask(Width), R, P, S, D, W),
            walk_concat(Rest, M, Offset + Width, R, P, S, D, W1);
        error ->
            add_unknown({missing_node, A}, W)
    end.

%% Full-width operational operands preserve uncertainty without pruning by electrical values.
-spec walk_all([binary()], data | control, plan(), sample(), non_neg_integer(), walk()) -> walk().
walk_all(Args, R, P = #{nodes := Nodes}, S, D, W) ->
    lists:foldl(
        fun(A, Acc) ->
            case maps:find(A, Nodes) of
                {ok, #{width := Width}} -> walk(A, mask(Width), R, P, S, D, Acc);
                error -> add_unknown({missing_node, A}, Acc)
            end
        end,
        W,
        Args
    ).

%% Highest selected bit bounds carry dependencies for ordinary unsigned arithmetic.
-spec highest_bit(pos_integer()) -> non_neg_integer().
highest_bit(1) -> 0;
highest_bit(N) -> 1 + highest_bit(N bsr 1).

%% Union masks by role; the same source can supply data and control independently.
-spec add_mask(data | control, binary(), non_neg_integer(), walk()) -> walk().
add_mask(_, _, 0, W) ->
    W;
add_mask(Role, Name, M, W) ->
    Key =
        case Role of
            data -> data_masks;
            control -> control_masks
        end,
    Values = maps:get(Key, W),
    W#{Key := Values#{Name => maps:get(Name, Values, 0) bor M}}.

%% Unknown leaves are retained explicitly and deduplicated when returning a query.
-spec add_unknown(term(), walk()) -> walk().
add_unknown(Reason, W = #{unknown := Reasons}) ->
    Text = iolist_to_binary(io_lib:format("~tp", [Reason])),
    W#{unknown := [Text | Reasons]}.

%% Return only public evidence, dropping query traversal caches.
-spec finish(non_neg_integer() | unknown, [binary()], walk()) -> result().
finish(Value, Selected, W) ->
    #{
        value => Value,
        selected => Selected,
        data_masks => maps:get(data_masks, W),
        control_masks => maps:get(control_masks, W),
        unknown => lists:usort(maps:get(unknown, W))
    }.

%% Unsupported target bindings and ambiguous writes supply no fabricated source masks.
-spec unknown_result(term()) -> result().
unknown_result(Reason) -> finish(unknown, [], add_unknown(Reason, empty_walk())).
