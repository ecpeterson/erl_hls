%%%% Shared effect-window wiring for compact and materialized topologies.
-module(xls_effect_window_dslx).
-moduledoc false.
-export([channels/1, spawn/1, arguments/2]).

-doc "Declares or connects the observation channels required by the chosen options.".
-spec arguments(nonempty_maybe_improper_list(),map()) -> [[[any()],...]].
arguments(Domains, #{effect_window_domain := Domain, effect_window_position := Position}) ->
    Stem = effect_window_domain_stem(Domain, Domains),
    [[Stem, "_", Port, "[u32:", integer_to_list(Position), "]"] ||
        Port <- ["request_p", "grant_c", "release_p"]].

-doc "Declares request, grant and release channels for each effect-window domain.".
-spec channels([any()]) -> [[[any()],...]].
channels(Domains) ->
    [effect_window_domain_channels(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

%% Declares the bounded arbitration channels for one independent domain.
-spec effect_window_domain_channels(integer(),[any()],nonempty_maybe_improper_list()) -> iodata().
effect_window_domain_channels(Index, Members, Domains) ->
    Count = integer_to_list(length(Members)),
    Stem = effect_window_domain_stem(Index, Domains),
    [
        effect_window_domain_comment(Index, Members, Domains),
        "    let (", Stem, "_request_p, ", Stem, "_request_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_request\");\n",
        "    let (", Stem, "_grant_p, ", Stem, "_grant_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_grant\");\n",
        "    let (", Stem, "_release_p, ", Stem, "_release_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_release\");\n"
    ].

-doc "Connects each effect-window domain to its ownership arbiter.".
-spec spawn([any()]) -> [[[any()],...]].
spawn(Domains) ->
    [effect_window_domain_spawn(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

%% Connects one domain's request, grant and release vectors.
-spec effect_window_domain_spawn(integer(),[any()],nonempty_maybe_improper_list()) -> iodata().
effect_window_domain_spawn(Index, Members, Domains) ->
    Stem = effect_window_domain_stem(Index, Domains),
    [
        "    spawn effect_window::Arbiter<u32:",
        integer_to_list(length(Members)), ">(\n",
        "      ", Stem, "_request_c, ", Stem, "_grant_p,\n",
        "      ", Stem, "_release_c);\n"
    ].

%% Creates a collision-free channel prefix for a domain.
-spec effect_window_domain_stem(integer(),nonempty_maybe_improper_list()) -> [string() | 95 | 99 | 100 | 101 | 102 | 105 | 110 | 111 | 116 | 119,...].
effect_window_domain_stem(0, [_OnlyDomain]) ->
    "effect_window";
effect_window_domain_stem(Index, [_ | _]) ->
    ["effect_window_domain_", integer_to_list(Index)].

%% Lists the schedulers that share one ownership domain.
-spec effect_window_domain_comment(integer(),[any()],nonempty_maybe_improper_list()) -> [[any()]].
effect_window_domain_comment(_Index, _Members, [_OnlyDomain]) -> [];
effect_window_domain_comment(Index, Members, [_ | _]) ->
    [
        "    // Effect-window domain ", integer_to_list(Index),
        ": schedulers ", lists:join(", ", [integer_to_list(Member)
            || Member <- Members]), ".\n"
    ].
