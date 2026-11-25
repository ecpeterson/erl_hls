#!/usr/bin/env escript
%% Check the independent two-bit transition oracle and publish only the observed word's lifetime.
-mode(compile).

-spec main([string()]) -> ok.
main([Directory, Samples, Output]) ->
    {ok, Terms} = file:consult(Samples),
    {Rows, [{complete, 8}]} = lists:split(8, Terms),
    {ok, [#{build := Build}]} = file:consult(filename:join(Directory, "identity.term")),
    {ok, Rtl} = file:read_file(filename:join(Directory, "design.v")),
    #{rtl := RtlDigest} = Build,
    RtlDigest = binary:encode_hex(crypto:hash(sha256, Rtl), lowercase),
    Epoch = <<"witness">>,
    Version = #{id => <<"initial">>, incarnation => Epoch, producer => root, origin => initial,
        storage => #{resource => <<"q">>, address => 0}, evidence => <<"Sampled initial q=2">>},
    {8, _, _, Events, Versions} = lists:foldl(fun transition/2, {0, 2, <<"initial">>, [], [Version]}, Rows),
    Bundle = #{format => spacetime, schema => 1, unit => cycle, evidence => simulation_witness, build => Build,
        capture => #{device => <<"RTL">>, clock => <<"clock">>, first_cycle => 0, end_cycle => 8, complete => true,
            evidence => <<"Eight simulated rising edges, including synchronous register reset">>,
            incarnations => [#{id => Epoch, first_cycle => 0, end_cycle => 8}],
            observers => [#{id => <<"pins">>, first_sequence => 0, next_sequence => 8, gaps => [],
                scope => <<"Word q at each fixture clock">>}]},
        resources => [#{id => <<"q">>, kind => ff, evidence => <<"Explicit top.q[1:0]">>, width => 2, depth => 1,
            ports => #{<<"write">> => write}, read_latency => 0, collision => read_first, reset => reinitialize}],
        events => lists:reverse(Events), versions => lists:reverse(Versions), activity => [], relations => [], physical => null},
    _ = hls_spacetime_artifact:write_bundle(Bundle, Output),
    ok.

%% Check the two independently specified functions, reset priority, enabled writes and disabled hold.
-spec transition(tuple(), tuple()) -> tuple().
transition({Cycle, Reset, Enable, Old, D, New}, {Cycle, Old, Last, Events, Versions}) ->
    A = Old band 1, B = Old bsr 1,
    D = ((1 bxor B) bsl 1) bor (A bxor B),
    New = case {Reset, Enable} of {1, _} -> 0; {0, 0} -> Old; {0, 1} -> D end,
    Seq = integer_to_binary(Cycle),
    Id = <<"edge/",Seq/binary>>,
    Common = #{id => Id, observer => <<"pins">>, sequence => Cycle, cycle => Cycle, incarnation => <<"witness">>,
        actor => <<"top">>, task => <<"clock">>, activation => Id, evidence => <<"Observed reset/enable and D/Q">>},
    Access = #{resource => <<"q">>, address => 0, port => <<"write">>},
    case Reset bor Enable of
        0 ->
            Hold = Common#{operation => <<"hold">>, inputs => [Last], outputs => [],
                access => Access#{kind => hold, version => Last}},
            {Cycle+1, New, Last, [Hold|Events], Versions};
        1 ->
            Next = <<"q/",Seq/binary>>,
            Write = Common#{operation => <<"write">>, inputs => [Last], outputs => [Next],
                access => Access#{kind => write, before => Last, after_version => Next, mask => 3}},
            V = #{id => Next, incarnation => <<"witness">>, producer => Id, origin => event,
                storage => #{resource => <<"q">>, address => 0}, evidence => <<"Observed committed edge">>},
            {Cycle+1, New, Next, [Write|Events], [V|Versions]}
    end.
