-module(xls_clocked_controller_tests).
-moduledoc "Admission tests and isolated generated controller units for the external XLS component check.".
-include_lib("eunit/include/eunit.hrl").
-export([write/1]).

%% Clocked control must not erase retained caller ownership or internal steps.
-spec rejects_retained_server_test() -> ok.
rejects_retained_server_test() ->
    ?assertException(error, {hls_diagnostic, #{code := unsupported_clocked_controller}},
        xls_clocked_controller:artifact("test/hls_server_reply_fixture.erl", 10)).

%% An ordinary multi-phase actor must keep its clocked entry and mailbox owner.
-spec rejects_state_machine_test() -> ok.
rejects_state_machine_test() ->
    ?assertException(error, {hls_diagnostic, #{code := unsupported_clocked_controller}},
        xls_clocked_controller:artifact("test/hls_domain_counter.erl", 10)).

-doc "Writes every shipped clocked controller as an isolated typed source unit; XLS checks both the actual shared transitions and the immediate adapter.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Kernels = [{hls_runtime, "runtime/hls_domain_lifecycle.erl"},
               {hls_runtime, "runtime/hls_supervisor_lifecycle.erl"},
               {hls_fabric, "runtime/domain/hls_domain_channel.erl"},
               {hls_fabric, "runtime/domain/hls_domain_channel_tx.erl"},
               {hls_fabric, "runtime/domain/hls_domain_channel_rx.erl"}],
    [begin
        Source = hls_source:library_file(App, Name),
        {ok, Parsed} = hls_source:parse_file(Source),
        Forms = hls_records:resolve(Parsed),
        Names = lists:append([Tags || {attribute, _, hls_tags, Tags} <- Forms]),
        Width = lists:max([hls_records:width(hls_records:find(Forms, Tag)) || Tag <- Names]),
        Words = max(10, (Width + 31) div 32),
        Output = filename:join(Stage, filename:basename(Name, ".erl")),
        ok = filelib:ensure_dir(filename:join(Output, "controller.x")),
        Artifact = xls_clocked_controller:artifact(Source, Words),
        ok = xls_emitted:write(Artifact, filename:join(Output, "controller.x")),
        ok = file:write_file(filename:join(Output, "frame_config.x"),
            xls_frame_layout:config(hls_frame_layout:new(Words)), [exclusive])
    end || {App, Name} <- Kernels],
    ok.
