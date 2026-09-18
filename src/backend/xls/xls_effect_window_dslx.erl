%%%% Shared effect-window wiring for compact and materialized topologies.
-module(xls_effect_window_dslx).
-moduledoc false.
-export([channels/1, spawn/1, arguments/2]).

arguments(Domains, #{effect_window_domain := Domain, effect_window_position := Position}) ->
    Stem = effect_window_domain_stem(Domain, Domains),
    [[Stem, "_", Port, "[u32:", integer_to_list(Position), "]"] ||
        Port <- ["request_p", "grant_c", "release_p"]].

channels(Domains) ->
    [effect_window_domain_channels(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

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

spawn(Domains) ->
    [effect_window_domain_spawn(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

effect_window_domain_spawn(Index, Members, Domains) ->
    Stem = effect_window_domain_stem(Index, Domains),
    [
        "    spawn effect_window::Arbiter<u32:",
        integer_to_list(length(Members)), ">(\n",
        "      ", Stem, "_request_c, ", Stem, "_grant_p,\n",
        "      ", Stem, "_release_c);\n"
    ].

effect_window_domain_stem(0, [_OnlyDomain]) ->
    "effect_window";
effect_window_domain_stem(Index, [_ | _]) ->
    ["effect_window_domain_", integer_to_list(Index)].

effect_window_domain_comment(_Index, _Members, [_OnlyDomain]) -> [];
effect_window_domain_comment(Index, Members, [_ | _]) ->
    [
        "    // Effect-window domain ", integer_to_list(Index),
        ": schedulers ", lists:join(", ", [integer_to_list(Member)
            || Member <- Members]), ".\n"
    ].

