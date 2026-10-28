-module(xls_provider_prng).
-moduledoc "Compiler companion for hls_prng. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([transpile/3]).

-doc "Emits the three masked xorshift32 steps, retaining each intermediate binding in clause order.".
-spec transpile(xorshift32, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
transpile(xorshift32, [State0], ClauseState0) ->
    ClauseState1 = xls_clause_lower:instr(ClauseState0, [
        "(",
        State0,
        " ^ (",
        State0,
        " << u32:13)) & u32:0xffffffff"
    ]),
    State1 = xls_clause_lower:reference(ClauseState1),
    ClauseState2 = xls_clause_lower:instr(ClauseState1, [
        "(",
        State1,
        " ^ (",
        State1,
        " >> u32:17)) & u32:0xffffffff"
    ]),
    State2 = xls_clause_lower:reference(ClauseState2),
    xls_clause_lower:instr(ClauseState2, [
        "(",
        State2,
        " ^ (",
        State2,
        " << u32:5)) & u32:0xffffffff"
    ]).
