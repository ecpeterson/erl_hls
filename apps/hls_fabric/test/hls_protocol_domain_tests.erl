-module(hls_protocol_domain_tests).
-moduledoc "Domain writers enforce crossing ownership and retain configured provider source snapshots.".
-include_lib("eunit/include/eunit.hrl").

%% Even a source-free input must fail at the ownership boundary before compilation is attempted.
-spec closed_entry_points_reject_partition_test() -> ok.
closed_entry_points_reject_partition_test() ->
    Config = #{native_actors => [a]},
    lists:foreach(fun(Emit) ->
        ?assertException(error, {hls_diagnostic, #{stage := domain, code := crossing_owner_required}},
            Emit(Config))
    end, [fun hls_protocol_domain:emit/1,
        fun(C) -> hls_protocol_domain:emit(C, raw) end,
        fun(C) -> hls_protocol_domain:emit(C, stream) end]).

%% Partition emission is explicit in both the entry point and source placement.
-spec partition_requires_selection_test() -> ok.
partition_requires_selection_test() ->
    ?assertException(error,
        {hls_diagnostic, #{stage := domain, code := partition_selection_required}},
        hls_protocol_domain:emit_partition(#{})).

%% A rejected writer must not create a directory or partially emitted source bundle.
-spec closed_writer_rejects_partition_test() -> ok.
closed_writer_rejects_partition_test() ->
    Config = #{native_actors => [a]},
    lists:foreach(fun(Write) ->
        ?assertException(error, {hls_diagnostic, #{code := crossing_owner_required}},
            Write(Config, "unused-domain-partition-output"))
    end, [fun hls_protocol_domain:write/2, fun hls_protocol_domain:write_stream/2]).

%% Exercise map and terms-file inputs with a small provider tree, without running XLS.
-spec provider_snapshot_test_() -> term().
provider_snapshot_test_() -> {timeout, 120, fun provider_snapshot/0}.

%% Raw and framed bundles bind the same caller-owned provider bytes and import namespace.
-spec provider_snapshot() -> ok.
provider_snapshot() ->
    Root = filename:join("_build", "domain-provider-" ++
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    Provider = filename:join(Root, "provider"),
    Bytes = <<"// A provider type retained by source packaging.\npub type Word = u32;\n">>,
    ok = filelib:ensure_dir(filename:join(Provider, "provider_word.x")),
    try
        ok = file:write_file(filename:join(Provider, "provider_word.x"), Bytes),
        Config = #{sources => [{"apps/hls_fabric/test/hls_domain_counter.erl", []},
                {"apps/hls_fabric/test/hls_domain_relay.erl", []}],
            topology => {hls_domain_counter, topology, []}, actor_limit => 2,
            control => rectangle, dslx_path => [Provider]},
        ConfigFile = filename:join(Root, "config.erl"),
        ok = file:write_file(ConfigFile, io_lib:format("~tp.~n", [Config])),
        lists:foreach(fun({Name, Input, Write}) ->
            Output = filename:join(Root, Name),
            #{units := [#{dslx_path := Imports}], inputs := Inputs} = Write(Input, Output),
            Relative = <<"support/import0/provider_word.x">>,
            ?assert(lists:member(<<"support/import0">>, Imports)),
            ?assertEqual({ok, Bytes}, file:read_file(filename:join(Output, Relative))),
            ?assertEqual([hls_generated_files:hash(Bytes)],
                [Hash || #{file := File, sha256 := Hash} <- Inputs, File =:= Relative]),
            case Name of
                "stream" ->
                    {ok, Stream} = file:read_file(filename:join(Output, "domain/domain_stream.x")),
                    ?assertNotEqual(nomatch, binary:match(Stream, <<"transport_fault: false">>)),
                    ?assertEqual(nomatch, binary:match(Stream, <<"fabric_fault:">>));
                "raw" -> ok
            end
        end, [{"raw", Config, fun hls_protocol_domain:write/2},
            {"stream", unicode:characters_to_binary(ConfigFile),
                fun hls_protocol_domain:write_stream/2}]),
        ok
    after
        file:del_dir_r(Root)
    end.
