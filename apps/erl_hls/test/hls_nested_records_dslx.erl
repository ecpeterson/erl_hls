-module(hls_nested_records_dslx).
-moduledoc false.
-export([write/1, mismatch_source/1]).

-doc "Writes normal actor DSLX with BEAM-derived transition witnesses and a matching RTL testbench.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    lists:foreach(fun(Kind) ->
        Path = filename:join(Stage, "nested_wrong_" ++ atom_to_list(Kind) ++ ".erl"),
        ok = file:write_file(Path, mismatch_source(Kind)),
        ok = file:write_file(filename:rootname(Path) ++ ".x", xls_parse:to_xls(Path))
    end, [nested, expression_case, empty_case, field_access]),
    Cases = [witness({sample, {vector2, X, Y}, Valid})
        || X <- [0, 1, 15, 31], Y <- [-64, -1, 0, 63], Valid <- [false, true]],
    Actor = xls_parse:to_xls("test/hls_nested_records_fixture.erl"),
    ok = file:write_file(filename:join(Stage, "nested_records.x"), [Actor, transition(),
        "\n#[test]\nfn host_agreement() {\n",
        [io_lib:format("  assert_eq(nested_transition(bits[13]:~p), bits[53]:~p);\n", [In, Out])
            || {In, Out} <- Cases], "}\n", backpressure()]),
    file:write_file(filename:join(Stage, "nested_records_tb.sv"), [
        "module nested_records_tb;\nreg [12:0] payload; wire [52:0] out;\n",
        "nested_records dut(.payload(payload), .out(out));\ninitial begin\n",
        [io_lib:format("payload=13'd~p; #1; if(out !== 53'd~p) $fatal(1, \"nested ~p: %h\", out);\n",
            [In, Out, In]) || {In, Out} <- Cases],
        " $display(\"PASS: 32 nested-record actor RTL witnesses\"); $finish;\nend\nendmodule\n"]).

-doc "Returns valid Erlang whose nominal record alternatives are outside the fixed-layout hardware subset.".
-spec mismatch_source(helper | nested | expression_case | empty_case | field_access) -> binary().
mismatch_source(Kind) ->
    {ok, Original} = file:read_file("test/hls_nested_records_fixture.erl"),
    Extra = <<"-record(other_vector, {x = hls_type:zero() :: hls_nums:uN(5), "
        "y = hls_type:zero() :: hls_nums:sN(7)}).\n"
        "-record(other_sample, {position = hls_type:zero() :: #vector2{}, "
        "valid = hls_type:zero() :: hls_bool:bool()}).\n">>,
    Source = binary:replace(Original, <<"-hls_data(cell).">>, <<"-hls_data(cell).\n", Extra/binary>>),
    case Kind of
        helper -> binary:replace(Source, <<"advance(Sample = #sample{valid = true">>,
            <<"advance(Sample = #other_sample{valid = true">>);
        nested -> binary:replace(Source, <<"Vector = #vector2{x = X}">>,
            <<"Vector = #other_vector{x = X}">>);
        expression_case -> binary:replace(binary:replace(Source,
            <<"#vector2{y = 0} ->">>, <<"#other_vector{y = 0} ->">>),
            <<"#vector2{} ->">>, <<"#other_vector{} ->">>);
        empty_case -> binary:replace(binary:replace(Source,
            <<"#vector2{y = 0} ->">>, <<"#other_vector{} ->">>),
            <<"#vector2{} ->">>, <<"_ ->">>);
        field_access -> binary:replace(Source, <<")#vector2.y">>, <<")#other_vector.y">>)
    end.

%% The expected bytes come from normal host callbacks and the generated host codec.
-spec witness(tuple()) -> {non_neg_integer(), non_neg_integer()}.
witness(Sample) ->
    Module = hls_nested_records_fixture,
    Message = {snapshot, Sample},
    {ok, boot, Initial} = Module:init([]),
    {active, Cell, consume} = Module:boot(cast, Message, Initial),
    {Cell, [{cast, out, Report}]} = Module:active(enter, boot, Cell),
    {hls_codec:unsigned(Module:pack(Message)),
        (hls_codec:unsigned(Module:pack(Cell)) bsl 26) bor hls_codec:unsigned(Module:pack(Report))}.

%% Exercise the emitted dispatcher and entry outcome, rather than a substitute expression lowerer.
-spec transition() -> string().
transition() -> """

pub fn nested_transition(payload: bits[13]) -> bits[53] {
  let frame = axis::pack(Tag::SNAPSHOT as u8, hls_bits::frame_payload(payload));
  let (phase, data, directive, repeat, failure) = dispatch(frame, Phase::BOOT, initial_actor_state().data);
  let outcome = enter(Phase::BOOT, phase, data);
  let effect = entry_effect(outcome.effects, u8:0);
  let failed = hls_failure::failed(failure) || hls_failure::failed(outcome.failure) ||
      directive != Directive::CONSUME || repeat || entry_effect_count(outcome.effects) != u8:1;
  (failed as u1) ++ bits_from_cell(data) ++ (effect.frame.payload as bits[26])
}
""".

%% The generated direct actor must retain its nested state while an entry's output is blocked.
-spec backpressure() -> string().
backpressure() -> """

#[test]
fn output_backpressure() {
  let empty = zero!<axis::Frame>();
  let ready = machine_step(initial_machine(), empty, false, true);
  let sample = Snapshot { sample: Sample { position: Vector2 { x: u5:31, y: s7:-4 }, valid: true } };
  let frame = axis::pack(Tag::SNAPSHOT as u8, hls_bits::frame_payload(bits_from_snapshot(sample)));
  let accepted = machine_step(ready.machine, frame, true, false);
  assert_eq(accepted.machine.phase, Phase::ACTIVE);
  assert_eq(accepted.machine.data.current.position.x, u5:0);
  let stalled = for (_, machine): (u32, Machine) in u32:0..u32:4 {
    let step = machine_step(machine, empty, false, false);
    assert_eq(step.egress_valid, false);
    assert_eq(step.machine, machine);
    step.machine
  }(accepted.machine);
  let emitted = machine_step(stalled, empty, false, true);
  assert_eq(emitted.egress_valid, true);
  assert_eq(emitted.egress.frame.header.op, Tag::REPORT as u8);
  assert_eq(report_from_bits(emitted.egress.frame.payload).current, stalled.data.current);
  assert_eq(report_from_bits(emitted.egress.frame.payload).previous, zero!<Sample>());
  assert_eq(emitted.machine.failure, hls_failure::NONE);
}
""".
