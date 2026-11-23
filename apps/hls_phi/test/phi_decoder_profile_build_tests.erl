-module(phi_decoder_profile_build_tests).
-moduledoc "Small source-build checks for consistent profile artifacts, observation metadata and external RAM compilation inputs. These do not run XLS or establish hardware behavior.".
-include_lib("eunit/include/eunit.hrl").

%% Actual binding indices and optional gather channels replace assumptions about a bank count.
-spec ram_configurations_test() -> ok.
ram_configurations_test() ->
    ?assertEqual(<<>>, iolist_to_binary(xls_scheduler_ram_v:configurations([]))),
    Configurations = iolist_to_binary(xls_scheduler_ram_v:configurations([
        #{index => 7, gather_members => 4}, #{index => 2}])),
    [State, Mailbox, Gather, OtherState, OtherMailbox] = entries(Configurations),
    ?assertEqual([<<"scheduler_7_state">>, <<"1R1W">>,
        <<"_scheduler_7_ram_read_req_out">>, <<"_scheduler_7_ram_read_resp_in">>,
        <<"_scheduler_7_ram_write_req_out">>, <<"_scheduler_7_ram_write_resp_in">>], State),
    ?assertEqual([<<"scheduler_7_mailbox">>, <<"scheduler_7_gather">>,
        <<"scheduler_2_state">>, <<"scheduler_2_mailbox">>],
        [hd(Entry) || Entry <- [Mailbox, Gather, OtherState, OtherMailbox]]),
    ?assertEqual([<<"scheduler_7_gather">>, <<"1R1W">>,
        <<"_scheduler_7_gather_read_req_out">>, <<"_scheduler_7_gather_read_resp_in">>,
        <<"_scheduler_7_gather_write_req_out">>, <<"_scheduler_7_gather_write_resp_in">>], Gather).

%% A rectangular single-plane build checks that normalization reaches every emitted artifact.
-spec single_plane_test_() -> term().
single_plane_test_() -> {timeout, 60, fun single_plane/0}.

%% Two cells split across two phi executors still share one source scheduler.
-spec single_plane() -> ok.
single_plane() ->
    #{files := Files, result := #{requirements := Requirements, topology := Topology}} =
        phi_decoder_profile_build:emit(#{shape => [2, 1], planes => [z], shards => 2}, #{}),
    ?assertEqual(#{phi_halo_cell => #{shared_service => aggregate_only, frame_payload_words => 3},
        phi_syndrome_replay_cell => #{shared_service => ordinary, frame_payload_words => 3}}, Requirements),
    ?assertEqual([phi_z, syndrome_z], lists:sort([Id || #{id := Id} <- maps:get(families, Topology)])),
    ?assertMatch(#{<<"width">> := 2, <<"height">> := 1, <<"planes">> := [<<"z">>],
        <<"scheduler_count">> := 3, <<"source_scheduler_count">> := 1,
        <<"phi_actor_count">> := 2, <<"source_actor_count">> := 2},
        document(Files, "phi_decoder_profile.json")),
    Wrapper = bytes(Files, "phi_decoder_profile_top.v"),
    ?assertNotEqual(nomatch, binary:match(Wrapper, <<"assign x_decoder_event_valid = 1'b0;">>)),
    ?assertEqual(nomatch, binary:match(bytes(Files, "phi_decoder_profile_topology.x"), <<"phi_x">>)),
    check_bundle(Files, 3, 4, false).

%% Observation and effect-window options must agree across actor code, topology and shell.
-spec observed_profile_test_() -> term().
observed_profile_test_() -> {timeout, 60, fun observed_profile/0}.

%% Both planes exercise separate effect domains while keeping passive observation ports ready.
-spec observed_profile() -> ok.
observed_profile() ->
    #{files := Files} = phi_decoder_profile_build:emit(
        #{shape => [2, 2], planes => [z, x], shards => 1},
        #{mailbox_debug => true, effect_window_partition => weak_components}),
    ?assertMatch(#{<<"planes">> := [<<"x">>, <<"z">>], <<"scheduler_count">> := 4,
        <<"phi_actor_count">> := 8, <<"source_actor_count">> := 8},
        document(Files, "phi_decoder_profile.json")),
    [begin
        ?assertNotEqual(nomatch, binary:match(bytes(Files, Name), <<"mailbox_debug_out">>))
    end || Name <- ["phi_halo_cell.x", "phi_syndrome_replay_cell.x"]],
    Generated = bytes(Files, "phi_decoder_profile_topology.x"),
    ?assertEqual(2, length(binary:matches(Generated, <<"spawn effect_window::Arbiter">>))),
    check_bundle(Files, 4, 16, true).

%% Misspelled build options and unsupported physical choices reject at the source-build boundary.
-spec invalid_options_test() -> ok.
invalid_options_test() ->
    Config = #{shape => [1, 1], planes => [x], shards => 1},
    ?assertError({unknown_profile_build_options, [scheduler_groups]},
        phi_decoder_profile_build:emit(Config, #{scheduler_groups => #{}})),
    ?assertError({mailbox_debug, enabled},
        phi_decoder_profile_build:emit(Config, #{mailbox_debug => enabled})),
    ?assertError({effect_window_partition, per_actor},
        phi_decoder_profile_build:emit(Config, #{effect_window_partition => per_actor})),
    ?assertException(error, _, phi_decoder_profile_build:emit(Config#{shards := 2}, #{})).

%% Source hashes, projected banks and physical interfaces describe the same emitted population.
-spec check_bundle(map(), pos_integer(), pos_integer(), boolean()) -> ok.
check_bundle(Files, Schedulers, Actors, Debug) ->
    #{<<"version">> := 1, <<"inputs">> := Hashes, <<"ram_configurations">> := Configurations} =
        document(Files, "phi_decoder_profile.inputs.json"),
    Helpers = [Name || Name <- maps:keys(Files), lists:suffix("/phi_direction.x", Name)],
    ?assertEqual(1, length(Helpers)),
    Names = Helpers ++ ["phi_halo_cell.x", "phi_syndrome_replay_cell.x", "phi_decoder_profile_topology.x",
        "phi_decoder_profile_top.v", "phi_decoder_profile.json", "phi_decoder_profile.build-profile.json"],
    ?assertEqual(lists:sort([list_to_binary(Name) || Name <- Names]), lists:sort(maps:keys(Hashes))),
    [?assertEqual(binary:encode_hex(crypto:hash(sha256, bytes(Files, Name)), lowercase),
        maps:get(list_to_binary(Name), Hashes)) || Name <- Names],
    ?assertEqual(hls_diagnostic:json_value(hls_build_profile:experiment(#{})),
        document(Files, "phi_decoder_profile.build-profile.json")),
    #{<<"banks">> := Banks} = document(Files, "phi-actors.json"),
    ?assertEqual(Schedulers, length(Banks)),
    ?assertEqual(Actors, lists:sum([length(Members) || #{<<"actors">> := Members} <- Banks])),
    [?assertEqual(Debug, maps:is_key(<<"mailbox">>, Bank)) || Bank <- Banks],
    Rams = entries(Configurations),
    ?assertEqual(2 * Schedulers, length(Rams)),
    RamNames = [Name || [Name | _] <- Rams],
    [?assert(lists:member(Ram, RamNames)) || #{<<"ram">> := Ram} <- Banks],
    Topology = bytes(Files, "phi_decoder_profile_topology.x"),
    Wrapper = bytes(Files, "phi_decoder_profile_top.v"),
    lists:foreach(fun(Entry) -> check_ram(Entry, Topology, Wrapper) end, Rams),
    ?assertEqual(Debug, binary:match(Wrapper, <<"_mailbox_debug_out_rdy(1'b1)">>) =/= nomatch),
    ok.

%% Codegen channels and the shell's physical RAM signals must both exist for every bank.
-spec check_ram([binary()], binary(), binary()) -> ok.
check_ram([Ram, <<"1R1W">>, ReadRequest, ReadResponse, WriteRequest, WriteResponse], Topology, Wrapper) ->
    ?assertNotEqual(nomatch, binary:match(Wrapper, <<Ram/binary, "_rd_addr">>)),
    lists:foreach(fun(<<"_", Port/binary>>) ->
        ?assertNotEqual(nomatch, binary:match(Topology, Port))
    end, [ReadRequest, ReadResponse, WriteRequest, WriteResponse]).

%% Each XLS configuration consists of a bank, its RAM kind and four channel names.
-spec entries(binary()) -> [[binary()]].
entries(Configurations) ->
    [binary:split(Entry, <<":">>, [global]) || Entry <- binary:split(Configurations, <<",">>, [global])].

%% Metadata is tested as a consumer sees it, after JSON serialization.
-spec document(map(), string()) -> map().
document(Files, Name) -> json:decode(bytes(Files, Name)).

%% Generated files may contain either binaries or nested IO data.
-spec bytes(map(), string()) -> binary().
bytes(Files, Name) -> iolist_to_binary(maps:get(Name, Files)).
