-module(phi_domain_repetition_live_tests).
-moduledoc "Source-only deployment-contract checks for Phi's same-clock and independent-endpoint live modes. These cases inspect ordinary supervisor declarations and reject inconsistent retained metadata before any FIFO is opened; they do not execute the application or hardware.".
-include_lib("eunit/include/eunit.hrl").

%% The established entry point still declares the exact same domain-first dependent group.
-spec same_clock_children_test() -> ok.
same_clock_children_test() ->
    Owner = self(), Channel = self(),
    {ok, {Flags, Children}} = phi_domain_repetition_live:init({domains(Owner), crossings(), Channel}),
    ?assertEqual(#{strategy => one_for_all, intensity => 3, period => 60}, Flags),
    ExpectedDomains = [#{id => Id, start => {hls_domain_instance, start_link,
        [Owner, Id, #{lifetime => supervised}]}, restart => permanent, shutdown => 10000, type => worker}
        || Id <- [a, b]],
    ExpectedLinks = [#{id => {channel, I}, start => {hls_domain_channel_instance, start_link,
        [Channel, I, {Owner, role(Source)}, {Owner, role(Destination)},
            #{poll_ms => 25, request_timeout_ms => 3000}]},
        restart => permanent, shutdown => 10000, type => worker}
        || #{index := I, source_domain := Source, destination_domain := Destination} <- crossings()],
    ?assertEqual(ExpectedDomains ++ ExpectedLinks, Children).

%% Every cut resolves TX and RX on its actual role, after both supervised domain lifetimes.
-spec independent_children_test() -> ok.
independent_children_test() ->
    Owner = self(), Peer = spawn(fun() -> receive stop -> ok end end), Namespace = 16#123456789abcdef0,
    try
        Adapters = #{0 => Owner, 1 => Peer},
        {ok, {#{strategy := one_for_all}, [A, B | Links]}} = phi_domain_repetition_live:init(
            {domains(Owner), crossings(), #{mode => independent_endpoints,
                adapters => Adapters, namespace => Namespace}}),
        ?assertMatch(#{id := a, start := {hls_domain_instance, start_link, _}}, A),
        ?assertMatch(#{id := b, start := {hls_domain_instance, start_link, _}}, B),
        ?assertEqual(8, length(Links)),
        [begin
            ?assertEqual({channel, I}, maps:get(id, Child)),
            ?assertEqual({hls_domain_endpoint_pair, start_link,
                [{maps:get(Source, Adapters), I}, {maps:get(Destination, Adapters), I},
                    {Owner, role(Source)}, {Owner, role(Destination)}, Namespace,
                    #{poll_ms => 25, request_timeout_ms => 3000}]}, maps:get(start, Child)),
            ?assertMatch(#{restart := permanent, shutdown := 10000, type := worker}, Child)
        end || {#{index := I, source_domain := Source, destination_domain := Destination}, Child} <-
            lists:zip(crossings(), Links)],
        ok
    after Peer ! stop end.

%% Cold-start namespace selection is explicit and cannot silently truncate to the wire width.
-spec namespace_bounds_test() -> ok.
namespace_bounds_test() ->
    with_metadata(fun(Bundle, Network, Stage) ->
        [?assertError({endpoint_live, namespace}, phi_domain_repetition_live:run(Bundle, Stage,
            #{mode => independent_endpoints, network_bundle => Network, namespace => Namespace}))
            || Namespace <- [0, -1, 1 bsl 64]],
        ?assertEqual({ok, []}, file:list_dir(Stage))
    end).

%% A network emitted for different domain inputs cannot connect to this live source bundle.
-spec retained_domain_mismatch_test() -> ok.
retained_domain_mismatch_test() ->
    with_metadata(fun(Bundle, Network, Stage) ->
        ok = file:write_file(filename:join([Network, "evidence", "domain-interface.etf"]),
            term_to_binary(#{domains => [], crossings => []})),
        ?assertError({endpoint_live, retained_domain_interface},
            phi_domain_repetition_live:run(Bundle, Stage, options(Network))),
        ?assertEqual({ok, []}, file:list_dir(Stage))
    end).

%% One adapter per physical role is required even when both duplicate rows are individually valid.
-spec duplicate_role_test() -> ok.
duplicate_role_test() ->
    with_metadata(fun(Bundle, Network, Stage) ->
        ok = write_roles(Network, [network_role(0), network_role(0)]),
        ?assertError({endpoint_live, role_indices},
            phi_domain_repetition_live:run(Bundle, Stage, options(Network))),
        ?assertEqual({ok, []}, file:list_dir(Stage))
    end).

%% The parser and packet router must preserve the original crossing's direction and complete membership.
-spec mismatched_endpoint_directions_test() -> ok.
mismatched_endpoint_directions_test() ->
    with_metadata(fun(Bundle, Network, Stage) ->
        Row = #{management := Management = #{interface := Interface = #{endpoints := [First | Rest]}}} = network_role(0),
        Wrong = Row#{management := Management#{interface := Interface#{endpoints := [First#{kind := rx} | Rest]}}},
        ok = write_roles(Network, [Wrong, network_role(1)]),
        ?assertError({endpoint_live, endpoint_directions},
            phi_domain_repetition_live:run(Bundle, Stage, options(Network))),
        Missing = Row#{management := Management#{interface := Interface#{endpoints := Rest}}},
        ok = write_roles(Network, [Missing, network_role(1)]),
        ?assertError({endpoint_live, endpoint_directions},
            phi_domain_repetition_live:run(Bundle, Stage, options(Network))),
        ?assertEqual({ok, []}, file:list_dir(Stage))
    end).

%% Attached mode checks identities before adopting any caller-owned broker or invoking inspection.
-spec attached_metadata_rejection_test() -> ok.
attached_metadata_rejection_test() ->
    with_metadata(fun(Bundle, Network, Stage) ->
        ok = file:write_file(filename:join([Network, "evidence", "domain-interface.etf"]), <<"wrong">>),
        ?assertError({endpoint_live, retained_domain_interface},
            phi_domain_repetition_live:run_attached(Bundle, Stage, options(Network),
                #{roles => #{}, inspect => fun(_, _) -> error(unexpected_inspection) end})),
        ?assertEqual({ok, []}, file:list_dir(Stage))
    end).

%% Metadata-only tests never establish sessions or allocate durable domain incarnation files.
-spec with_metadata(fun((file:filename(), file:filename(), file:filename()) -> term())) -> ok.
with_metadata(Fun) ->
    Root = filename:join("_build", "phi-independent-live-" ++ integer_to_list(erlang:unique_integer([positive]))),
    Bundle = filename:join(Root, "domain"), Network = filename:join(Root, "network"),
    Stage = filename:join(Root, "live"),
    ok = filelib:ensure_dir(filename:join([Network, "evidence", "domain-interface.etf"])),
    ok = filelib:ensure_dir(filename:join(Bundle, "fixture.etf")),
    ok = file:make_dir(Stage),
    Interface = term_to_binary(#{domains => domains(self()), crossings => crossings()}),
    ok = file:write_file(filename:join(Bundle, "fixture.etf"), term_to_binary(#{actors => []}), [exclusive]),
    ok = file:write_file(filename:join(Bundle, "interface.etf"), Interface, [exclusive]),
    ok = file:write_file(filename:join([Network, "evidence", "domain-interface.etf"]), Interface, [exclusive]),
    ok = write_roles(Network, [network_role(0), network_role(1)]),
    try Fun(Bundle, Network, Stage), ok
    after ok = file:del_dir_r(Root) end.

%% Valid independent options carry a full-width namespace distinct from the management session.
-spec options(file:filename()) -> phi_domain_repetition_live:transport().
options(Network) -> #{mode => independent_endpoints, network_bundle => Network,
    namespace => 16#123456789abcdef0}.

%% Minimal trusted role descriptors preserve the emitted list-of-components envelope.
-spec write_roles(file:filename(), [map()]) -> ok.
write_roles(Network, Rows) -> file:write_file(filename:join(Network, "interface.etf"), term_to_binary(Rows)).

%% Each component declares the same static endpoint direction; unrelated source metadata is unnecessary here.
-spec network_role(0 | 1) -> map().
network_role(Index) ->
    Endpoints = [#{id => I, kind => case Source of Index -> tx; _ -> rx end} ||
        #{index := I, source_domain := Source} <- crossings()],
    Interface = #{kind => domain_endpoint_management, management_route => {0, 2}, response_tag => 129,
        endpoints => Endpoints, codecs => #{operation => {hls_type, hls_enum, enum, [[tick, bind, fence]]},
            status => {hls_type, hls_enum, enum, [[ok, accepted, stale, invalid, busy, closed, exhausted]]},
            binding => {hls_type, hls_record, endpoint_binding, [{Field, hls_nums:u64()} ||
                Field <- [namespace, generation, source_incarnation, destination_incarnation]]}}},
    #{role => #{domain_index => Index, endpoints => Endpoints},
        packets => #{routes => Endpoints}, management => #{interface => Interface},
        network => #{domain_index => Index}}.

%% Domain enumeration is the existing source placement's a/b order.
-spec domains(pid()) -> [map()].
domains(Owner) -> [#{id => a, index => 0, owner => Owner}, #{id => b, index => 1, owner => Owner}].

%% Four crossings in each direction match the retained selected repetition placement.
-spec crossings() -> [map()].
crossings() -> [#{index => I, source_domain => 0, destination_domain => 1} || I <- [1, 17, 26, 50]] ++
    [#{index => I, source_domain => 1, destination_domain => 0} || I <- [8, 28, 37, 61]].

%% Convert retained numeric role indices only at the supervisor's deployment-owner boundary.
-spec role(0 | 1) -> a | b.
role(0) -> a;
role(1) -> b.
