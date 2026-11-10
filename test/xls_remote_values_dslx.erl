-module(xls_remote_values_dslx).
-moduledoc "Generates finite direct-owner DSLX witnesses against the remote-helper actor's ordinary BEAM callbacks.".
%% External-tool regression fixture generation.
-export([write/1]).

-doc "Writes a generated actor and sixty finite entry assertions into an existing directory; expected results come from BEAM.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {ok, Semantics} = file:read_file("test_data/xls_static_actions_semantics.inc.x"),
    Artifact = xls_parse:to_artifact("test/xls_remote_values_fixture.erl"),
    Cases = [{Index, Phase, Value, Ready}
        || {Index, Phase} <- lists:enumerate(0, phases()),
           Value <- [0, 1, 2, 3], Ready <- [16#ffff, 16#aaa0, 0]],
    Tests = [assertion(Case) || Case <- Cases],
    Bytes = [xls_emitted:bytes(Artifact), Semantics,
         "\n// Sixty finite BEAM outcomes, each observed through sixteen direct-owner clocks.\n",
         "#[test]\nfn remote_values_match_beam() {\n", Tests, "}\n"],
    xls_emitted:write(xls_emitted:with_bytes(Artifact, Bytes),
        filename:join(Stage, "xls_remote_values.x")).

%% Keep the actor's declared phase order explicit in the finite oracle.
-spec phases() -> [atom()].
phases() -> [nested, discarded, arguments, selected, tupled].

%% An exception means no state/effect commitment; successful lists retain their source order.
-spec oracle(atom(), non_neg_integer()) -> {boolean(), non_neg_integer(), [{atom(), non_neg_integer()}]}.
oracle(Phase, Value) ->
    try xls_remote_values_fixture:Phase(enter, Phase, {cell, Value}) of
        {{cell, Next}, Actions} ->
            {false, Next, [{Port, Payload} || {cast, Port, {value, Payload}} <- Actions]}
    catch error:{badmatch, _} -> {true, Value, []}
    end.

%% The fixture's nonzero ready masks both drain its two-effect maximum within sixteen clocks.
-spec expected(atom(), non_neg_integer(), non_neg_integer()) -> bitstring().
expected(Phase, Value, Ready) ->
    {Failed, Next, Effects} = oracle(Phase, Value),
    {Pending, Data, Accepted} = case {Failed, Effects, Ready} of
        {true, _, _} -> {false, Value, []};
        {false, [], _} -> {false, Next, []};
        {false, _, 0} -> {true, Value, []};
        _ -> {false, Next, Effects}
    end,
    Ports = [port(Port) || {Port, _} <- Accepted],
    Values = [Payload || {_, Payload} <- Accepted],
    <<(bit(Failed)):1, (bit(Pending)):1, Data:32, (length(Accepted)):8,
      (list_to_binary(pad(Ports)))/binary,
      (<< <<Payload:32>> || Payload <- pad(Values) >>)/binary>>.

%% Render one exact expected result rather than duplicating the callback algorithm in DSLX.
-spec assertion({non_neg_integer(), atom(), non_neg_integer(), non_neg_integer()}) -> iodata().
assertion({Index, Phase, Value, Ready}) ->
    <<Expected:122>> = expected(Phase, Value, Ready),
    io_lib:format("  assert_eq(static_entry_probe(u8:~p, u32:~p, u16:~p), bits[122]:0x~.16B);\n",
        [Index, Value, Ready, Expected]).

%% Reserve two output positions, matching the finite fixture's maximum batch.
-spec pad([non_neg_integer()]) -> [non_neg_integer()].
pad(Values) -> Values ++ lists:duplicate(2 - length(Values), 0).

%% Pack Boolean outcomes in the same order as the DSLX probe.
-spec bit(boolean()) -> 0 | 1.
bit(false) -> 0;
bit(true) -> 1.

%% Port numbers follow the actor's explicit interface declaration.
-spec port(first | second | third) -> 0..2.
port(first) -> 0;
port(second) -> 1;
port(third) -> 2.
