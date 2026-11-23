-module(hls_ring_source_dslx).
-export([write/1]).
-doc "Writes two-dispatch native witnesses for source-lowered enum and nested-record rings.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    M = hls_ring_fixture,
    Requests = [{request, Mode, Flag} || Mode <- [cold, warm, hot], Flag <- [false, true]],
    Cases = [witness(A,B) || A <- Requests, B <- Requests],
    {ok,active,S} = M:init([]), Width = bit_size(M:pack(S)),
    MessageWidth = bit_size(M:pack(hd(Requests))), InWidth = 2 * MessageWidth,
    Artifact = xls_parse:to_artifact("apps/erl_hls/test/hls_ring_fixture.erl"),
    Probe = io_lib:format("\npub fn ring_source_probe(payload: bits[~p]) -> bits[~p] {\n"
        "let a = axis::pack(Tag::REQUEST as u8, hls_bits::frame_payload(payload[~p+:bits[~p]]));\n"
        "let b = axis::pack(Tag::REQUEST as u8, hls_bits::frame_payload(payload[0+:bits[~p]]));\n"
        "let (_,first,_,_,f1) = dispatch(a,Phase::ACTIVE,initial_actor_state().data);\n"
        "let (_,second,_,_,f2) = dispatch(b,Phase::ACTIVE,first);\n"
        "((hls_failure::failed(f1) || hls_failure::failed(f2)) as u1) ++ bits_from_cell(second)\n}\n",
        [InWidth, Width+1, MessageWidth, MessageWidth, MessageWidth]),
    Bytes = [xls_emitted:bytes(Artifact), Probe, "#[test]\nfn native_agreement() {\n",
        [io_lib:format("assert_eq(ring_source_probe(bits[~p]:~p),bits[~p]:~p);\n",
            [InWidth,I,Width+1,O]) || {I,O} <- Cases], "}\n"],
    ok = xls_emitted:write(xls_emitted:with_bytes(Artifact, Bytes), filename:join(Stage,"ring_source.x")),
    file:write_file(filename:join(Stage,"ring_source_tb.sv"), [
        io_lib:format("module ring_source_tb; reg [~p:0] payload; wire [~p:0] out;\n"
            "ring_source dut(.payload(payload),.out(out)); initial begin\n", [InWidth-1,Width]),
        [io_lib:format("payload=~p'd~p; #1; if(out !== ~p'd~p) $fatal(1,\"ring source %h\",out);\n",
            [InWidth,I,Width+1,O]) || {I,O} <- Cases],
        "$display(\"PASS 36 ring source witnesses\"); $finish; end endmodule\n"]).
%% The runtime callbacks and codec supply independent expected state bits.
-spec witness(tuple(), tuple()) -> {non_neg_integer(), non_neg_integer()}.
witness(A,B) ->
    M=hls_ring_fixture, {ok,active,S}=M:init([]),
    {active,S1,consume}=M:active(cast,A,S), {active,S2,consume}=M:active(cast,B,S1),
    {hls_codec:unsigned(<<(M:pack(A))/bitstring,(M:pack(B))/bitstring>>), hls_codec:unsigned(M:pack(S2))}.
