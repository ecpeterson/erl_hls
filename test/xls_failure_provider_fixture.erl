-module(xls_failure_provider_fixture).
-moduledoc "Unregistered test provider with a fallible operation, exercising source-origin propagation.".
-export([checked/1, transpile/3]).

-doc "Returns a nonzero byte; zero raises badarg.".
-spec checked(byte()) -> 1..255.
checked(0) -> error(badarg);
checked(Value) -> Value.

-doc "Lowers the same zero check as a value/failure pair using the ordinary provider contract.".
-spec transpile(checked, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    {fallible, badarg, xls_clause_lower:ir()}.
transpile(checked, [Value], _State) ->
    {fallible, badarg, xls_dslx:tuple([Value, xls_dslx:binary('==', Value, "u8:0")])}.
