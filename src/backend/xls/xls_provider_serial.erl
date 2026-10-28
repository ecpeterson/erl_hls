-module(xls_provider_serial).
-moduledoc "Compiler companion for hls_serial. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, dslx_imports/0, transpile/3]).

-doc "Renders the unsigned fixed-width XLS representation.".
-spec print_type(counter, [pos_integer()]) -> xls_clause_lower:printable().
print_type(counter, Args) -> xls_nums:unsigned_type(hls_serial:width(counter, Args)).

-doc "Declares the static XLS serial-arithmetic companion.".
-spec dslx_imports() -> [atom()].
dslx_imports() -> [hls_serial].

-doc "Lowers counter construction and arithmetic, preserving half-range failures.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir()
    | xls_clause_lower:clause_state()
    | {fallible, badarg, xls_clause_lower:ir()}.
transpile(counter, [{static, integer, Width}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_serial:counter(Width)});
transpile(wrap, [{phantom, type, Type}, Value], _State) ->
    operand(Type, Value);
transpile(Operation, [{phantom, type, Type}, Left, Right], _State) when
    Operation =:= add; Operation =:= difference; Operation =:= before
->
    Call = [
        "hls_serial::",
        atom_to_list(Operation),
        "(",
        operand(Type, Left),
        ", ",
        operand(Type, Right),
        ")"
    ],
    case Operation of
        add -> Call;
        _ -> {fallible, badarg, Call}
    end.

%% Reduce literal values before emitting them; dynamic casts preserve their low
%% bits independently of signedness or source width. No expression is duplicated.
-spec operand(hls_type:descriptor(), xls_clause_lower:ir()) -> xls_clause_lower:ir().
operand(Type = {hls_type, hls_serial, counter, _}, {static, integer, Value}) ->
    [xls_type:print_type(Type), ":", integer_to_list(hls_serial:wrap(Type, Value))];
operand(Type = {hls_type, hls_serial, counter, _}, Value) ->
    ["(", Value, " as ", xls_type:print_type(Type), ")"].
