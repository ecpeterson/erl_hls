-module(hls_protocol_domain_tests).
-moduledoc "Explicit raw crossing ownership is required before partition source generation.".
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
