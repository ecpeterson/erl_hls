-module(telemetry_example_fixture).
-moduledoc "Independent telemetry arithmetic oracle and finite public-port vectors for the shipped example bundle.".
-include("../src/examples/telemetry/telemetry.hrl").

%% External regression generation and reusable CPU expectations.
-export([write/1, commands/0, oracle/1]).

%% One configuration or labeled raw sample; the example owns admission bounds.
-type command() :: #configure{} | #raw{}.
%% The oracle retains only one four-reading window, independently of actor state.
-type reading() :: {hls_nums:u16(), hls_nums:s16(), boolean()}.

-doc "Writes a fresh example bundle plus CPU-checked command/report vectors outside that bundle. Requires an existing stage; does not invoke XLS or simulate hardware.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Commands = commands(),
    Reports = oracle(Commands),
    Reports = telemetry:run(Commands),
    Example = telemetry:example_commands(),
    ExampleReports = oracle(Example),
    ExampleReports = telemetry:run(Example),
    _ = telemetry:write_bundle(filename:join(Stage, "bundle")),
    Partial = through_samples(Commands, 2),
    First = through_samples(Commands, 4),
    ok = memory(Stage, "commands.mem", [packet(Command) || Command <- Commands], 49),
    ok = memory(Stage, "partial.mem", [packet(Command) || Command <- Partial], 49),
    ok = memory(Stage, "first.mem", [packet(Command) || Command <- First], 49),
    Invalid = invalid_packets(),
    ok = memory(Stage, "invalid.mem", Invalid, 49),
    ok = memory(Stage, "expected.mem", [report_frame(Report) || Report <- Reports], 32),
    ok = file:write_file(filename:join(Stage, "cpu.term"), io_lib:format("~tp.~n", [Reports])),
    file:write_file(filename:join(Stage, "telemetry_vectors.svh"), [
        "// Counts accompany the independently checked BEAM transcript.\n",
        [io_lib:format("localparam integer ~s = ~B;~n", [Name, Count]) || {Name, Count} <- [
            {"COMMAND_COUNT", length(Commands)}, {"PARTIAL_COUNT", length(Partial)},
            {"FIRST_COUNT", length(First)}, {"INVALID_COUNT", length(Invalid)},
            {"REPORT_COUNT", length(Reports)}]]]).

-doc "Returns eight windows spanning signed limits, saturation, zero/max gain, opaque sequence labels and calibration changes within a window. The first sample deliberately precedes configuration.".
-spec commands() -> [command()].
commands() ->
    First = [#raw{sequence = 0, value = 100}, #configure{offset = -100, gain = 3},
        #raw{sequence = 1, value = -200}, #raw{sequence = 2, value = 20000},
        #raw{sequence = 3, value = -20000}],
    First ++ lists:append([window_commands(Window) || Window <- lists:seq(1, 7)]).

%% Reconfigure after two readings to make configuration ordering observable.
-spec window_commands(1..7) -> [command()].
window_commands(Window) ->
    First = case Window rem 3 of
        0 -> #configure{offset = -32768, gain = 255};
        1 -> #configure{offset = 0, gain = 1};
        2 -> #configure{offset = 32767, gain = 0}
    end,
    [First, #raw{sequence = 100 + Window, value = 32767},
        #raw{sequence = Window, value = -32768},
        #configure{offset = -Window, gain = Window},
        #raw{sequence = 65535 - Window, value = 10},
        #raw{sequence = 4 * Window + 3, value = -10}].

-doc "Evaluates complete windows with unbounded BEAM arithmetic and explicit signed16 clipping. It never invokes actor callbacks; initial postponed samples use the first configuration.".
-spec oracle([command()]) -> [#summary{}].
oracle([]) -> [];
oracle(Commands) ->
    {Waiting, [#configure{offset = Offset, gain = Gain} | Rest]} =
        lists:splitwith(fun(Command) -> is_record(Command, raw) end, Commands),
    summaries(Waiting ++ Rest, Offset, Gain, [], []).

%% Window membership follows input order; only calibration changes at configure.
-spec summaries([command()], hls_nums:s16(), hls_nums:u8(), [reading()], [#summary{}]) ->
    [#summary{}].
summaries([], _, _, [], Reports) -> lists:reverse(Reports);
summaries([], _, _, Window, _) -> error({incomplete_oracle_window, length(Window)});
summaries([#configure{offset = Offset, gain = Gain} | Rest], _, _, Window, Reports) ->
    summaries(Rest, Offset, Gain, Window, Reports);
summaries([#raw{sequence = Sequence, value = Raw} | Rest], Offset, Gain, Window, Reports) ->
    Unbounded = Raw * Gain + Offset,
    Value = max(-32768, min(32767, Unbounded)),
    Reading = {Sequence, Value, Value =/= Unbounded},
    case Window ++ [Reading] of
        Full = [_, _, _, _] ->
            Values = [V || {_, V, _} <- Full],
            Summary = #summary{sequence = Sequence, sum = lists:sum(Values),
                minimum = lists:min(Values), maximum = lists:max(Values),
                clipped = length([true || {_, _, true} <- Full])},
            summaries(Rest, Offset, Gain, [], [Summary | Reports]);
        Partial -> summaries(Rest, Offset, Gain, Partial, Reports)
    end.

%% Prefixes end immediately after the requested number of raw commands.
-spec through_samples([command()], non_neg_integer()) -> [command()].
through_samples(_, 0) -> [];
through_samples([Command = #raw{} | Rest], Count) ->
    [Command | through_samples(Rest, Count - 1)];
through_samples([Command = #configure{} | Rest], Count) ->
    [Command | through_samples(Rest, Count)].

%% The exact-only ingress uses an all-zero rectangle and its first u2 target.
-spec packet(command()) -> non_neg_integer().
packet(Command) -> flattened_frame(telemetry_calibrator, Command).

%% Poison samples must be discarded at ingress, before any actor state changes.
-spec invalid_packets() -> [non_neg_integer()].
invalid_packets() ->
    Good = packet(#raw{sequence = 999, value = 12345}),
    [Good bor (3 bsl 128),
        (Good band bnot(255 bsl 96)) bor (255 bsl 96),
        Good band bnot(255 bsl 120),
        Good bor (1 bsl (130 + 48)),
        Good bor (((1 bsl 48) bor (1 bsl 16)) bsl 130)].

%% Reports use the same public generated actor codecs as the host application.
-spec report_frame(#summary{}) -> non_neg_integer().
report_frame(Report) -> flattened_frame(telemetry_window, Report).

%% XLS flattens Frame {header,payload} with header above payload, unlike the
%% serialized axis::bits_from_frame convention. No private DUT state is exposed.
-spec flattened_frame(module(), tuple()) -> non_neg_integer().
flattened_frame(Module, Record) ->
    Packed = hls_codec:align(Module:pack(Record), 32),
    Header = ((bit_size(Packed) div 32) bsl 24) bor Module:pack_tag(element(1, Record)),
    (Header bsl 96) bor hls_codec:unsigned(Packed).

%% Fixed-width hexadecimal text is accepted directly by Verilog readmemh.
-spec memory(file:filename(), string(), [non_neg_integer()], pos_integer()) -> ok.
memory(Stage, Name, Values, Digits) ->
    file:write_file(filename:join(Stage, Name),
        [io_lib:format("~*.16.0b~n", [Digits, Value]) || Value <- Values]).
