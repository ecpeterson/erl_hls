-module(hls_spacetime_memory_fixture_tests).
-moduledoc """
Rejecting checks against a freshly recorded spacetime memory witness. No captured golden is embedded: the caller first obtains the real simulator trace, then these checks corrupt exactly one evidence condition at a time. Successful rejection checks establish validator behavior, not hardware correctness.
""".
%% Explicit local qualification entry, called after the positive RTL witness.
-export([check/2]).

-doc "Applies 14 deliberate corruptions to a trusted fresh trace and requires their specific rejection reasons. Returns the number checked; unexpected acceptance or another error fails.".
-spec check(file:filename(), hls_spacetime:build()) -> non_neg_integer().
check(Path, Build) ->
    {ok, Terms} = file:consult(Path),
    [Footer | ReverseRows] = lists:reverse(Terms),
    Rows = lists:reverse(ReverseRows),
    Cases = [
        {Rows, Footer#{complete := false}, unsupported_or_incomplete_capture},
        {Rows, Footer#{rows := 18}, footer_count},
        {[R || R <- Rows, maps:get(cycle, R) =/= 4],
            Footer#{rows := 16, end_cycle := 16}, cycle_coverage},
        {change(Rows, 8, #{cycle => 7}), Footer, cycle_coverage},
        {change(Rows, 5, #{write_mask => 1}), Footer, unsupported_mask},
        {change(Rows, 7, #{result_data => 0}), Footer, {response, 7, 16#a5, 0}},
        {change(Rows, 7, #{result_valid => 0}), Footer, {response, 7, 16#a5, 16#a5}},
        {change(Rows, 4, #{result_valid => 1, result_data => 16#a5}), Footer,
            {unexpected_response, 4}},
        {change(Rows, 8, #{old => [0, 16#5a]}), Footer, {between_edge_words, 8}},
        {change(Rows, 8, #{new => [0, 16#5a]}), Footer, {new_words, 8}},
        {change(Rows, 2, #{read_enable => 1, read_address => 1}), Footer,
            {uninitialized_read, 2, 1}},
        {Rows, Footer#{collision := write_first}, unsupported_or_incomplete_capture},
        {change(Rows, 11, #{result_valid => 1}), Footer, {reset, 11}},
        {change(Rows, 11, #{old => [0, 16#5a], new => [0, 16#5a]}), Footer,
            {between_edge_words, 11}}
    ],
    lists:foreach(fun({ChangedRows, ChangedFooter, Reason}) ->
        reject(fun() -> hls_spacetime_memory_fixture:bundle(ChangedRows, ChangedFooter, Build) end,
            Reason)
    end, Cases),
    length(Cases).

%% Change only the selected sampled cycle; all other recorded data remains intact.
-spec change([map()], non_neg_integer(), map()) -> [map()].
change(Rows, Cycle, Changes) ->
    [case maps:get(cycle, R) of Cycle -> maps:merge(R, Changes); _ -> R end || R <- Rows].

%% Require the intended condition, so another parser error cannot masquerade as a useful rejection.
-spec reject(fun(() -> term()), term()) -> ok.
reject(Fun, Reason) ->
    try Fun() of
        _ -> error({accepted_corrupt_memory_trace, Reason})
    catch
        error:{spacetime_memory_fixture, Reason} -> ok
    end.
