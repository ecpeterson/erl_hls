-module(hls_enum_collection_dslx).
-moduledoc false.
-export([write/1]).
-doc "Writes 36 two-update BEAM witnesses and matching DSLX/RTL assertions into an existing directory.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Inputs = [{request, Index, Mode} || Index <- [1, 2], Mode <- [idle, busy, done]],
    Cases = [witness(A, B) || A <- Inputs, B <- Inputs],
    Artifact = xls_parse:to_artifact("apps/erl_hls/test/hls_enum_collection_fixture.erl"),
    Bytes = [xls_emitted:bytes(Artifact), probe(),
        "\n#[test]\nfn host_agreement() {\n",
        [io_lib:format("  assert_eq(collection_probe(u8:~p), bits[13]:~p);\n", [In, Out])
         || {In, Out} <- Cases], "}\n"],
    ok = xls_emitted:write(xls_emitted:with_bytes(Artifact, Bytes), filename:join(Stage, "enum_collection.x")),
    file:write_file(filename:join(Stage, "enum_collection_tb.sv"), [
        "module enum_collection_tb;\nreg [7:0] payload; wire [12:0] out;\n",
        "enum_collection dut(.payload(payload), .out(out));\ninitial begin\n",
        [io_lib:format("payload=8'd~p; #1; if(out !== 13'd~p) $fatal(1, \"enum collection ~p: %h\", out);\n",
            [In, Out, In]) || {In, Out} <- Cases],
        "$display(\"PASS: 36 enum collection RTL witnesses\"); $finish;\nend\nendmodule\n"]).

%% Host codec and callbacks are independent of generated helper names or encodings.
-spec witness(tuple(), tuple()) -> {non_neg_integer(), non_neg_integer()}.
witness(A, B) ->
    M = hls_enum_collection_fixture,
    {ok, active, Initial} = M:init([]),
    {active, First, consume} = M:active(cast, A, Initial),
    {active, Second, consume} = M:active(cast, B, First),
    {hls_codec:unsigned(<<(M:pack(A))/bitstring, (M:pack(B))/bitstring>>),
     hls_codec:unsigned(M:pack(Second))}.

%% Two dispatches expose both replacement and preservation of the other slot.
-spec probe() -> string().
probe() -> """

pub fn collection_probe(payload: u8) -> bits[13] {
  let a = axis::pack(Tag::REQUEST as u8, hls_bits::frame_payload(payload[4+:u4]));
  let b = axis::pack(Tag::REQUEST as u8, hls_bits::frame_payload(payload[0+:u4]));
  let (_, first, _, _, f1) = dispatch(a, Phase::ACTIVE, initial_actor_state().data);
  let (_, second, _, _, f2) = dispatch(b, Phase::ACTIVE, first);
  ((hls_failure::failed(f1) || hls_failure::failed(f2)) as u1) ++ bits_from_cell(second)
}
""".
