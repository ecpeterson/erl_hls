-module(xls_clause_lower).
-moduledoc "Lowers normalized callback expressions while retaining evaluation order, variable scope and the first selected failure. Actor/helper lowerers and type-provider transpile callbacks share this internal state API. Renderable values use xls_dslx nodes and opaque provider leaves; compile-time phantom types stay here. print/1 is a terminal renderer, so containing modules retain fragments until xls_emitted allocates failure metadata.".
%% Lower complete clauses or advance one expression.
-export([branch_from_clause/4, branch_from_clause/6, clause_outcome/4, statement_from_statement/2]).
%% Read and propagate the selected outcome and failure.
-export([outcome_value/1, failure_expression/1, failure_code/1, add_match_failure/3, add_failure/2]).
%% Binding and statement operations used by sibling lowerers and type providers.
-export([find_binding/3, bind/4, record_raw/2, reference/1, reference/2, instr/2, instr/3]).
%% Terminal rendering; enclosing modules normally finalize through xls_emitted.
-export([print/1]).
-export_type([ir/0, printable/0, static/0, phantom/0, clause_state/0, outcome/0]).
-include("xls_clause_lower.hrl").

%% Clause values add compile-time type arguments to the shared DSLX syntax.
%% Provider snippets remain opaque leaves; phantom types cannot be rendered.
-doc "Untyped source numbers retained until a consuming operation determines their hardware type.".
-type static() :: {static, integer, integer()} | {static, float, float()}.
-doc "Compile-time type arguments accepted by provider callbacks, never emitted as runtime values.".
-type phantom() :: {phantom, type, hls_type:descriptor()}.
-doc "Renderable values use the shared DSLX syntax, static literals and opaque provider leaves.".
-type printable() :: xls_dslx:value().
-doc "Clause values additionally admit compile-time-only type descriptors.".
-type ir() :: printable() | phantom() | [ir()].

-doc "Renders clause values through the shared DSLX renderer; phantom types are rejected.".
-spec print(printable()) -> iodata() | char().
print(Value) -> xls_dslx:render(Value).

-doc "Clause-local bindings, emitted statements and selected failures; branches carry their own copy.".
-type clause_state() :: #clause_state{}.

-spec branch_from_clause(
    erl_parse:abstract_clause(),
    [printable()],
    atom(),
    fun((printable()) -> printable())
) -> {printable(), printable()}.
-doc "Processes an Erlang clause from handle_*/2 into XLS.".
branch_from_clause(Clause, ArgVals, StateName, Postprocessor) ->
    ComputeState = lower_clause(Clause, ArgVals, StateName, #{}),
    Failure = [
        "let s = zero!<State>();\n",
        "    (axis::pack(Tag::ERROR as u8, (",
        failure_kind(ComputeState),
        ") as u32), ",
        "(Tag::STATE, s))"
    ],
    branch_from_state(ComputeState, Postprocessor, Failure).

-doc "Lowers one clause with caller-supplied failure output and enum encodings; guards are selected by the caller.".
-spec branch_from_clause(
    erl_parse:abstract_clause(),
    [printable()],
    atom(),
    fun((printable()) -> printable()),
    printable(),
    #{atom() => printable()}
) ->
    {printable(), printable()}.
branch_from_clause(
    Clause,
    ArgVals,
    StateName,
    Postprocessor,
    Failure,
    EnumAtoms
) ->
    ComputeState = lower_clause(Clause, ArgVals, StateName, EnumAtoms),
    branch_from_state(ComputeState, Postprocessor, Failure).

%% Apply the result conversion only in the successful branch.
-spec branch_from_state(clause_state(), fun((printable()) -> printable()), printable()) ->
    {printable(), printable()}.
branch_from_state(ComputeState, Postprocessor, Failure) ->
    OutState = instr(ComputeState, [
        "if (",
        failure_expression(ComputeState),
        ") {\n",
        "    ",
        Failure,
        "\n",
        "} else {\n",
        "    ",
        Postprocessor(reference(ComputeState)),
        "\n",
        "}"
    ]),
    {lists:reverse(OutState#clause_state.statements), OutState#clause_state.reference}.

%% Keep the computed value and its selected failure together. Consumers may
%% commit a compound result only when the whole callback has succeeded.
-doc "A lowered callback retains ordered statements, its value and the first selected failure.".
-type outcome() :: #{
    body := [printable()], result := printable(), failed := printable(), failure := printable()
}.

-doc "Lowers a callback clause to statements, result and first-failure expressions without rendering them.".
-spec clause_outcome(erl_parse:abstract_clause(), [printable()], atom(), map()) -> outcome().
clause_outcome(Clause, ArgVals, StateName, EnumAtoms) ->
    State = lower_clause(Clause, ArgVals, StateName, EnumAtoms),
    #{
        body => lists:reverse(State#clause_state.statements),
        result => reference(State),
        failed => failure_expression(State),
        failure => failure_code(State)
    }.

%% Bind callback arguments before lowering the annotated body in source order.
-spec lower_clause(erl_parse:abstract_clause(), [printable()], atom(), #{atom() => printable()}) ->
    clause_state().
lower_clause(
    {clause, _Line, ArgPatterns, _Guards, Body},
    ArgVals,
    StateName,
    EnumAtoms
) ->
    InjectMatch = fun
        F({{match, LineNo, LHS, RHS}, Arg}) ->
            {match, LineNo, LHS, F({RHS, Arg})};
        F({X, Arg}) ->
            {match, element(2, X), X, Arg}
    end,
    BigBody =
        case ArgPatterns of
            [{nil, _L}] -> Body;
            _ -> lists:map(InjectMatch, lists:zip(ArgPatterns, ArgVals)) ++ Body
        end,
    lists:foldl(
        fun(Statement, State) ->
            statement_from_statement(Statement, State#clause_state{reference = none})
        end,
        #clause_state{state_name = StateName, enum_atoms = EnumAtoms},
        xls_var_scope:annotate(BigBody)
    ).

-spec statement_from_statement(erl_parse:abstract_expr(), clause_state()) -> clause_state().
-doc """
Main transpiler workhorse.  Recursively converts a complex `erl_parse`
expression into a sequence of simple emitted XLS expressions.
""".
%% Private normalization nodes, introduced after source analysis. Mapping a
%% selected value into a common backend type lets case arms retain different
%% source shapes without moving their computations across a branch boundary.
statement_from_statement({xls_live, _Line, Live, Expression}, State) ->
    Lowered = statement_from_statement(Expression, State#clause_state{live_bindings = Live}),
    Lowered#clause_state{live_bindings = State#clause_state.live_bindings};
statement_from_statement({xls_map, _Line, Expression, Render}, State) ->
    Evaluated = statement_from_statement(Expression, State),
    instr(Evaluated#clause_state{reference = none}, Render(reference(Evaluated)));
%% A guard sequence has its own exception boundary. An arithmetic failure
%% rejects this sequence; it must neither fail the actor nor prevent a later
%% semicolon alternative from matching. Earlier body failures remain intact.
statement_from_statement({xls_guard, _Line, Expression}, State) ->
    Evaluated = statement_from_statement(Expression, State#clause_state{failures = []}),
    Guard = instr(Evaluated, [
        "!(",
        failure_expression(Evaluated),
        ") && (",
        reference(Evaluated),
        ")"
    ]),
    Guard#clause_state{failures = State#clause_state.failures};
statement_from_statement({block, _Line, Expressions}, State) ->
    lower_expression_sequence(Expressions, State);
statement_from_statement(String, State) when is_list(String) ->
    reference(State, String);
statement_from_statement({atom, _L, true}, State) ->
    reference(State, "bool:1");
statement_from_statement({atom, _L, false}, State) ->
    reference(State, "bool:0");
statement_from_statement(
    {atom, _L, Atom},
    State = #clause_state{
        enum_atoms = EnumAtoms
    }
) ->
    reference(
        State,
        maps:get(Atom, EnumAtoms, xls_names:enum_member(Atom))
    );
statement_from_statement({var, Line, Name}, State) ->
    case find_binding(Name, Line, State) of
        {ok, Value} -> reference(State, Value);
        error -> error({unbound_xls_variable, Line, Name})
    end;
statement_from_statement({integer, _L, Integer}, State) ->
    reference(State, {static, integer, Integer});
%% A signature gives this literal its width without casting an existing value.
statement_from_statement({xls_typed_integer, _L, Type, Integer}, State) ->
    reference(State, [Type, ":", integer_to_list(Integer)]);
statement_from_statement({char, _L, Integer}, State) ->
    reference(State, {static, integer, Integer});
statement_from_statement({op, _L, '+', {integer, _IntegerLine, Integer}}, State) ->
    reference(State, {static, integer, Integer});
statement_from_statement({float, _L, Float}, State) ->
    reference(State, {static, float, Float});
statement_from_statement({op, _L, '+', {float, _FloatLine, Float}}, State) ->
    reference(State, {static, float, Float});
statement_from_statement({op, _L, '-', {float, _FloatLine, Float}}, State) ->
    reference(State, {static, float, -Float});
%% Preserve signed literals for width-directed conversions such as wrap/2.
statement_from_statement({op, _L, '-', {integer, _IntegerLine, Integer}}, State) ->
    reference(State, {static, integer, -Integer});
statement_from_statement({op, Line, 'andalso', Left, Right}, State) ->
    xls_case_lower:lower(
        Line,
        Left,
        [
            {clause, Line, [{atom, Line, true}], [], [Right]},
            {clause, Line, [{atom, Line, false}], [], [{atom, Line, false}]}
        ],
        State
    );
statement_from_statement({op, Line, 'orelse', Left, Right}, State) ->
    xls_case_lower:lower(
        Line,
        Left,
        [
            {clause, Line, [{atom, Line, true}], [], [{atom, Line, true}]},
            {clause, Line, [{atom, Line, false}], [], [Right]}
        ],
        State
    );
statement_from_statement({op, Line, Op, Left, Right}, State) when
    Op =:= 'bsl'; Op =:= 'bsr'
->
    {[Value, Count], Evaluated} = lower_arguments([Left, Right], State),
    lower_shift(Op, Value, Count, Line, Evaluated);
%% Integer facts are attached before callback/helper normalization.
statement_from_statement({xls_integer_compare, _Line, Op, Left, Right}, State) ->
    {References, Evaluated} = lower_arguments([Left, Right], State),
    instr(Evaluated, xls_comparison:lower(Op, References));
statement_from_statement(X, State) when is_tuple(X) andalso op == element(1, X) ->
    [op, Line, Op | Args] = tuple_to_list(X),
    {References, ArgState} = lower_arguments(Args, State),
    lower_operator(Op, References, Line, ArgState);
statement_from_statement({xls_bit_size, _, Name, Value}, State) ->
    Evaluated = statement_from_statement(Value, State),
    Size = ["hls_bits::length(", reference(Evaluated), ")"],
    instr(
        Evaluated,
        case Name of
            bit_size -> Size;
            byte_size -> ["((", Size, " + u32:7) / u32:8)"]
        end
    );
statement_from_statement(Binary = {bin, _, _}, State) ->
    xls_binary_lower:construct(Binary, State);
statement_from_statement({tuple, _L, Slots}, State) ->
    {BwdReferences, IntermediateState} = lists:foldl(
        fun(Slot, {References, ThisState}) ->
            NewState = statement_from_statement(Slot, ThisState#clause_state{reference = none}),
            {[NewState#clause_state.reference | References], NewState}
        end,
        {[], State},
        Slots
    ),
    instr(IntermediateState, ["(", [[Ref, ", "] || Ref <- lists:reverse(BwdReferences)], ")"]);
statement_from_statement({record, _L, NameAtom, Fields}, State) ->
    {BwdAssignments, IntermediateState} = lists:foldl(
        fun({record_field, _1, {atom, _2, FieldAtom}, RHS}, {Assignments, ThisState}) ->
            NewState = statement_from_statement(RHS, ThisState#clause_state{reference = none}),
            {[{FieldAtom, NewState#clause_state.reference} | Assignments], NewState}
        end,
        {[], State},
        Fields
    ),
    Assignments = lists:reverse(BwdAssignments),
    SecondState = instr(IntermediateState, [
        xls_names:record_type(record_name(NameAtom)),
        " {\n",
        [
            ["  ", atom_to_list(FieldAtom), ": ", Reference, ",\n"]
         || {FieldAtom, Reference} <- Assignments
        ],
        "  ..zero!<",
        xls_names:record_type(record_name(NameAtom)),
        ">()\n",
        "}"
    ]),
    instr(SecondState, record_value(NameAtom, reference(SecondState), SecondState));
statement_from_statement({record, _L, ToUpdate, NameAtom, UpdateFields}, State) ->
    InputState = statement_from_statement(ToUpdate, State),
    {BwdAssignments, IntermediateState} = lists:foldl(
        fun({record_field, _1, {atom, _2, FieldAtom}, RHS}, {Assignments, ThisState}) ->
            NewState = statement_from_statement(RHS, ThisState#clause_state{reference = none}),
            {[{FieldAtom, NewState#clause_state.reference} | Assignments], NewState}
        end,
        {[], InputState},
        UpdateFields
    ),
    Assignments = lists:reverse(BwdAssignments),
    SecondState = instr(IntermediateState, [
        xls_names:record_type(record_name(NameAtom)),
        " {\n",
        [
            ["  ", atom_to_list(FieldAtom), ": ", Reference, ",\n"]
         || {FieldAtom, Reference} <- Assignments
        ],
        "  ..",
        record_raw(NameAtom, ["(", InputState#clause_state.reference, ")"]),
        "\n",
        "}"
    ]),
    instr(SecondState, record_value(NameAtom, reference(SecondState), SecondState));
statement_from_statement({'if', Line, Clauses}, State) ->
    xls_case_lower:lower_if(Line, Clauses, State);
statement_from_statement({'case', Line, Condition, Clauses}, State) ->
    xls_case_lower:lower(Line, Condition, Clauses, State);
statement_from_statement({xls_helper_call, _Line, Name, Args}, State) ->
    {References, ArgState} = lower_arguments(Args, State),
    CallState = instr(ArgState, [Name, "(", lists:join(", ", References), ")"]),
    outcome_value(CallState);
statement_from_statement({call, Line, MF, Args}, State) ->
    {remote, _1, {atom, _2, Module}, {atom, _3, FAtom}} = MF,
    {References, ArgState} = lower_arguments(Args, State),
    case xls_type:transpile(Module, FAtom, References, ArgState) of
        X = #clause_state{} ->
            X;
        {fallible, Kind, Expression} ->
            Evaluated = instr(ArgState, Expression),
            Value = reference(Evaluated),
            Checked = add_failure(
                [
                    "hls_failure::check(",
                    Value,
                    ".1, ",
                    xls_failure_sites:at(Kind, Line),
                    ")"
                ],
                Evaluated
            ),
            reference(Checked, [Value, ".0"]);
        X ->
            instr(ArgState, X)
    end;
statement_from_statement({record_field, _L, Object, RecordAtom, {atom, _LL, SlotAtom}}, State) ->
    IntermediateState = statement_from_statement(Object, State),
    instr(IntermediateState, [
        record_raw(RecordAtom, reference(IntermediateState)), ".", atom_to_list(SlotAtom)
    ]);
statement_from_statement({match, _L, LHS, RHS}, State) ->
    RHSState = statement_from_statement(RHS, State),
    xls_pattern_lower:match(LHS, reference(RHSState), RHSState).

%% Evaluate operands left to right while retaining each intermediate reference.
-spec lower_arguments([erl_parse:abstract_expr()], clause_state()) -> {[ir()], clause_state()}.
lower_arguments(Args, State) ->
    lists:mapfoldl(
        fun(Arg, Acc) ->
            Next = statement_from_statement(Arg, Acc#clause_state{reference = none}),
            {reference(Next), Next}
        end,
        State,
        Args
    ).

%% Only untyped source integers use ERTS arithmetic. Provider results and
%% signature-directed values keep their existing XLS operand widths.
-spec lower_operator(atom(), [ir()], erl_anno:anno(), clause_state()) -> clause_state().
lower_operator(Op, References, Line, State) ->
    Integers = [N || {static, integer, N} <- References],
    Result =
        case length(Integers) =:= length(References) of
            true -> xls_static_integer:operation(Op, Integers);
            false -> error
        end,
    case Result of
        {ok, Value} -> reference(State, {static, integer, Value});
        error -> lower_runtime_operator(Op, References, Line, State)
    end.

%% A statically zero divisor has no successful result. Keep a harmless value
%% and the existing failure carrier, including any earlier selected failure.
-spec lower_runtime_operator(atom(), [ir()], erl_anno:anno(), clause_state()) -> clause_state().
lower_runtime_operator(Op, [_Left, {static, integer, 0}], Line, State) when
    Op =:= 'div'; Op =:= 'rem'
->
    division_failure({static, integer, 0}, Line, reference(State, {static, integer, 0}));
lower_runtime_operator(Op, References, Line, State) ->
    Evaluated = instr(State, op(Op, References)),
    case {Op, References} of
        {Division, [_Left, Right]} when Division =:= 'div'; Division =:= 'rem' ->
            division_failure(Right, Line, Evaluated);
        _ ->
            Evaluated
    end.

%% Shift operands have independent types: the result keeps the value's width,
%% while a signed count can reverse direction. Even literal counts use the
%% helper: DSLX rejects a primitive constexpr shift beyond the operand width.
-spec lower_shift('bsl' | 'bsr', ir(), ir(), erl_anno:anno(), clause_state()) -> clause_state().
lower_shift(Op, {static, integer, Value}, {static, integer, Count}, Line, State) ->
    lower_operator(Op, [{static, integer, Value}, {static, integer, Count}], Line, State);
lower_shift(_Op, {static, integer, _}, _Count, Line, _State) ->
    error({untyped_shift_value, Line, {use, hls_type, as, 2}});
lower_shift(Op, Value, {static, integer, Count}, Line, State) ->
    Direction =
        case {Op, Count < 0} of
            {'bsl', false} -> 'bsl';
            {'bsr', true} -> 'bsl';
            _ -> 'bsr'
        end,
    Magnitude = abs(Count),
    Literal = [xls_nums:index_type(Magnitude + 1), ":", integer_to_list(Magnitude)],
    lower_shift(Direction, Value, Literal, Line, State);
lower_shift(Op, Value, Count, _Line, State) ->
    Left =
        case Op of
            'bsl' -> "true";
            'bsr' -> "false"
        end,
    instr(State, ["hls_integer::shift<", Left, ">(", Value, ", ", Count, ")"]).

%% Preserve an earlier failure when a division adds a possible zero-divisor failure.
-spec division_failure(ir(), erl_anno:anno(), clause_state()) -> clause_state().
division_failure({static, integer, 0}, Line, State) ->
    add_failure(xls_failure_sites:at(badarith, Line), State);
division_failure({static, integer, _Nonzero}, _Line, State) ->
    State;
division_failure(Divisor, Line, State) ->
    add_failure(
        [
            "hls_failure::check(",
            Divisor,
            " == 0, ",
            xls_failure_sites:at(badarith, Line),
            ")"
        ],
        State
    ).

%% A selected outcome contributes one explicit failure kind. Its value
%% and any exported bindings remain separate from that bookkeeping.
-doc "Projects a value/failure pair and retains its failure in evaluation order.".
-spec outcome_value(clause_state()) -> clause_state().
outcome_value(State) ->
    Value = reference(State),
    reference(add_failure([Value, ".1"], State), [Value, ".0"]).

%% Discard intermediate values, retaining their statements and failures.
-spec lower_expression_sequence([erl_parse:abstract_expr()], clause_state()) -> clause_state().
lower_expression_sequence(Expressions, State0) ->
    lists:foldl(
        fun(Expression, State) ->
            statement_from_statement(
                Expression,
                State#clause_state{reference = none}
            )
        end,
        State0,
        Expressions
    ).

-doc "Returns the predicate that any selected computation in this clause failed.".
-spec failure_expression(clause_state()) -> printable().
failure_expression(#clause_state{failures = []}) -> "bool:false";
failure_expression(State) -> ["(", failure_code(State), ") != hls_failure::NONE"].

%% The list is stored in reverse evaluation order. A later failed computation
%% cannot replace an earlier failure, even if its placeholder value is used.
-doc "Projects the public error kind from the first selected failure code.".
-spec failure_kind(clause_state()) -> printable().
failure_kind(State) -> ["hls_failure::kind(", failure_code(State), ")"].

-doc "Returns the earliest selected failure, or NONE for a successful clause.".
-spec failure_code(clause_state()) -> printable().
failure_code(#clause_state{failures = []}) ->
    "hls_failure::NONE";
failure_code(#clause_state{failures = [Only]}) ->
    Only;
failure_code(#clause_state{failures = Failures}) ->
    %% A flat argument list avoids XLS's expression-nesting limit for callbacks
    %% with many failure sites. The static helper retains the right fold.
    ["hls_failure::first_all([", lists:join(", ", lists:reverse(Failures)), "])"].

-doc "Records a failed-match predicate at its source origin without discarding prior failures.".
-spec add_match_failure(printable(), erl_anno:anno(), clause_state()) -> clause_state().
add_match_failure(Predicate, Line, State) ->
    add_failure(
        [
            "hls_failure::check(",
            Predicate,
            ", ",
            xls_failure_sites:at(match_failure, Line),
            ")"
        ],
        State
    ).

-doc "Appends a selected failure-code expression in evaluation order.".
-spec add_failure(printable(), clause_state()) -> clause_state().
add_failure(Failure, State = #clause_state{failures = Failures}) ->
    State#clause_state{failures = [Failure | Failures]}.

%% A partially bound name stays unsafe even if a later expression attempts to
%% bind it again. Keep the originating join for a useful source diagnostic.
-doc "Finds a variable's current value, rejecting bindings unsafe across a branch join.".
-spec find_binding(atom(), erl_anno:anno(), clause_state()) ->
    {ok, printable()} | error.
find_binding(Name, Line, #clause_state{bindings = Bindings, unsafe_bindings = Unsafe}) ->
    case maps:find(Name, Unsafe) of
        {ok, Origin} -> error({unsafe_xls_variable, Line, Name, Origin});
        error -> maps:find(Name, Bindings)
    end.

-doc "Binds a fresh variable or checks equality with its existing value, recording a match failure on mismatch.".
-spec bind(atom(), erl_anno:anno(), printable(), clause_state()) -> clause_state().
bind(Name, Line, Value = {static, integer, _}, State) ->
    case find_binding(Name, Line, State) of
        error ->
            reference(
                State#clause_state{bindings = (State#clause_state.bindings)#{Name => Value}}, Value
            );
        {ok, _} ->
            bind_named(Name, Line, Value, State)
    end;
bind(Name, Line, Value, State) ->
    bind_named(Name, Line, Value, State).

%% Materialize runtime values once; repeated bindings retain their match check.
-spec bind_named(atom(), erl_anno:anno(), printable(), clause_state()) -> clause_state().
bind_named(Name, Line, Value, State) ->
    Previous = find_binding(Name, Line, State),
    {Emitted, Named} = uniquify(State, Name),
    Bound = instr(Named, Emitted, Value),
    Next =
        case Previous of
            {ok, Existing} -> add_match_failure([Existing, " != ", Emitted], Line, Bound);
            error -> Bound#clause_state{bindings = (Bound#clause_state.bindings)#{Name => Emitted}}
        end,
    reference(Next, Value).

-doc "Wraps actor data and messages in their ABI tuples, leaving internal records as values.".
-spec record_value(atom() | {value, atom()}, ir(), clause_state()) -> ir().
record_value({value, _Name}, Struct, _State) ->
    [Struct];
record_value(NameAtom, Struct, #clause_state{state_name = NameAtom}) ->
    ["(Tag::", xls_names:enum_member(NameAtom), ", ", Struct, ")"];
record_value(NameAtom, Struct, _State) ->
    [
        "(Tag::",
        xls_names:enum_member(NameAtom),
        ", ",
        Struct,
        ", ",
        "bits_from_",
        xls_names:record_codec(NameAtom),
        "(",
        Struct,
        "))"
    ].

-doc "Recovers the source name after representation selection.".
-spec record_name(atom() | {value, atom()}) -> atom().
record_name({value, Name}) -> Name;
record_name(Name) -> Name.

-doc "Projects callback tuples and constrains internal values to their nominal struct type.".
-spec record_raw(atom() | {value, atom()}, printable()) -> printable().
record_raw({value, Name}, Value) ->
    ["({ let value: ", xls_names:record_type(Name), " = ", Value, "; value })"];
record_raw(_Name, Value) ->
    [Value, ".1"].

%%%
%%% clause_state utilities
%%%

-spec uniquify(clause_state(), atom() | string()) ->
    {string(), clause_state()}.
-doc "Allocates a source binding in a namespace disjoint from generated types, codecs and helpers.".
uniquify(State, NameAtom) when is_atom(NameAtom) ->
    Name = atom_to_list(NameAtom),
    uniquify(State, Name);
uniquify(State = #clause_state{named_counters = Counters}, Name) ->
    Counter = maps:get(Name, Counters, 0) + 1,
    NamedCounters = Counters#{Name => Counter},
    %% Preserve the source convention for intentionally unused bindings.
    Prefix =
        case Name of
            [$_ | _] -> "_v_";
            _ -> "v_"
        end,
    NewName = Prefix ++ Name ++ [$_ | integer_to_list(Counter)],
    {NewName, State#clause_state{named_counters = NamedCounters}}.

-doc "Returns the most recently lowered value, or none before a value is produced.".
-spec reference(clause_state()) -> none | ir().
reference(ClauseState) ->
    ClauseState#clause_state.reference.

-doc "Selects the current value without emitting a statement or changing failures.".
-spec reference(clause_state(), ir()) -> clause_state().
reference(ClauseState, Reference) ->
    ClauseState#clause_state{reference = Reference}.

-doc "Allocates and emits one expression binding in the current clause.".
-spec instr(clause_state(), printable()) -> clause_state().
instr(#clause_state{anonymous_counter = Counter} = ClauseState, Expr) ->
    instr(
        ClauseState#clause_state{anonymous_counter = Counter + 1},
        [$_ | integer_to_list(Counter)],
        Expr
    ).

-doc "Retains one named binding without rewriting its expression; preserves evaluation order and failure tracking.".
-spec instr(clause_state(), xls_dslx:name(), printable()) -> clause_state().
instr(ClauseState, Place, Expr) ->
    ClauseState#clause_state{
        reference = Place,
        statements = [xls_dslx:bind(Place, Expr) | ClauseState#clause_state.statements]
    }.

%%%
%%% Dictionaries for built-in calls
%%%

-spec op(Op :: atom(), Args :: [printable()]) -> printable().
-doc "Lowers source operators to shared DSLX expressions or existing provider leaves; numeric comparisons are classified separately.".
op('+', [Value]) -> Value;
op('-', [Value]) -> xls_dslx:unary('-', Value);
op('+', [Left, Right]) -> xls_dslx:binary('+', Left, Right);
op('-', [Left, Right]) -> xls_dslx:binary('-', Left, Right);
op('*', [Left, Right]) -> [Left, " * ", Right];
op('div', [Left, Right]) -> [Left, " / ", Right];
op('rem', [Left, Right]) -> ["hls_integer::remainder(", Left, ", ", Right, ")"];
op('band', [Left, Right]) -> [Left, " & ", Right];
op('bor', [Left, Right]) -> [Left, " | ", Right];
op('bxor', [Left, Right]) -> xls_dslx:binary('^', Left, Right);
op('bnot', [Operand]) -> ["!", Operand];
op('not', [Operand]) -> ["!", Operand];
op('<', [Left, Right]) -> [Left, " < ", Right];
op('=<', [Left, Right]) -> [Left, " <= ", Right];
op('>', [Left, Right]) -> [Left, " > ", Right];
op('>=', [Left, Right]) -> [Left, " >= ", Right];
op('=:=', [Left, Right]) -> [Left, " == ", Right];
op('=/=', [Left, Right]) -> [Left, " != ", Right].
