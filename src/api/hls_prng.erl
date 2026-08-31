%%%% hls_prng
%%%%
%%%% Small deterministic pseudo-random primitives with matching BEAM and XLS
%%%% behavior.

-module(hls_prng).
-moduledoc """
Small deterministic pseudo-random primitives for lowerable Erlang code.

`xorshift32/1` advances a 32-bit xorshift generator by one step. Its state is
also its output, so callers keep the returned word and choose whichever bits
their protocol needs. The BEAM implementation masks every step to reproduce
the fixed-width arithmetic used by generated XLS.

A nonzero state traverses the generator's nonzero period. Zero is an absorbing
state and is accepted deliberately, which keeps this primitive a transparent
state transition rather than a seeding policy. This generator is suitable for
simulation fixtures and inexpensive randomized hardware behavior, not for
cryptography.
""".

-export([xorshift32/1, transpile/3]).

-define(U32_MASK, 16#ffffffff).

-doc "Advances one 32-bit xorshift state and returns the next state.".
-spec xorshift32(hls_nums:u32()) -> hls_nums:u32().
xorshift32(State0)
        when is_integer(State0), State0 >= 0, State0 =< ?U32_MASK ->
    State1 = (State0 bxor (State0 bsl 13)) band ?U32_MASK,
    State2 = (State1 bxor (State1 bsr 17)) band ?U32_MASK,
    (State2 bxor (State2 bsl 5)) band ?U32_MASK;
xorshift32(_State) ->
    error(badarg).

transpile(xorshift32, [State0], ClauseState0) ->
    ClauseState1 = xls_parse:instr(ClauseState0, [
        "(", State0, " ^ (", State0,
        " << u32:13)) & u32:0xffffffff"
    ]),
    State1 = xls_parse:reference(ClauseState1),
    ClauseState2 = xls_parse:instr(ClauseState1, [
        "(", State1, " ^ (", State1,
        " >> u32:17)) & u32:0xffffffff"
    ]),
    State2 = xls_parse:reference(ClauseState2),
    xls_parse:instr(ClauseState2, [
        "(", State2, " ^ (", State2,
        " << u32:5)) & u32:0xffffffff"
    ]).
