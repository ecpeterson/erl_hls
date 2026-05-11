-module(xls_types).
-export([from_erl/1, width/1, new/1]).
-export_type([u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0]).
-export_type([float64/0, float32/0, float16/0]).

%%% unsigned integers
-type u8() :: 0 .. (1 bsl 8 - 1).
-type u16() :: 0 .. (1 bsl 16 - 1).
-type u32() :: 0 .. (1 bsl 32 - 1).
-type u64() :: 0 .. (1 bsl 64 - 1).

%%% signed integers
-type s8() :: -(1 bsl 7) .. (1 bsl 7 - 1) .
-type s16() :: -(1 bsl 15) .. (1 bsl 15 - 1).
-type s32() :: -(1 bsl 31) .. (1 bsl 31 - 1).
-type s64() :: -(1 bsl 63) .. (1 bsl 63 - 1).

%%% floats
%%% NOTE: Erlang only understands float64, but it can write some other formats.
-type float64() :: float().  % e11m52
-type float32() :: float().  % e8m23
-type float16() :: float().  % e5m10

-spec from_erl(erl_parse:af_remote_type()) -> atom() | iolist().
from_erl({remote_type, _4, [{atom, _5, xls_types}, {atom, _6, Type}, []]}) ->
    Type;
from_erl({remote_type, _4, [{atom, _5, Module}, {atom, _6, Type}, Args]}) ->
    StripArg = fun
        ({atom, _L, Atom}) -> Atom;
        ({integer, _L, Integer}) -> Integer
    end,
    Module:type(Type, lists:map(StripArg, Args)).

width(u8) -> 8;
width(u16) -> 16;
width(u32) -> 32;
width(u64) -> 64;
width(s8) -> 8;
width(s16) -> 16;
width(s32) -> 32;
width(s64) -> 64;
width(float16) -> 16;
width(float32) -> 32;
width(float64) -> 64.

new(_) -> 0.
