-module(hls_spacetime_memory_fixture).
-moduledoc """
Converts the finite spacetime_memory_tb recording into a validated cycle artifact. The bench uses two real hls_1r1w_ram lanes and an extra response register; this helper checks every sampled word and response against its observed controls. It does not infer native BRAM placement or decoder behavior. Inputs are trusted local simulator terms in a fresh, bounded trace file.
""".
%% Fixture qualification and deliberately corrupted-record tests.
-export([read/2, bundle/3]).

%% Values are absent only for uninitialized RAM or an invalid response.
-type word() :: unknown | 0 .. ((1 bsl 8) - 1).
%% One complete pre-edge control sample and the resulting RAM contents.
-type row() :: #{cycle := non_neg_integer(), reset := 0 | 1,
    read_enable := 0 | 1, read_address := 0 | 1,
    write_enable := 0 | 1, write_address := 0 | 1,
    write_data := 0 .. ((1 bsl 8) - 1), write_mask := 0 .. ((1 bsl 8) - 1),
    old := [word()], new := [word()], result_valid := 0 | 1, result_data := word()}.
%% Mandatory completion counters from the simulator, never inferred from EOF.
-type footer() :: #{end_cycle := pos_integer(), rows := pos_integer(),
    complete := boolean(), collision := read_first}.
%% Pure reducer state; versions name operations rather than equal payload values.
-type state() :: #{inc := integer(), epoch_start := non_neg_integer(),
    last_reset := 0 | 1, seq := non_neg_integer(), events := [hls_spacetime:event()],
    versions := [hls_spacetime:version()], epochs := [map()], words := map(),
    pending := map(), writes := non_neg_integer(), equal_writes := non_neg_integer(),
    masked_writes := non_neg_integer(), collisions := non_neg_integer(),
    reads := non_neg_integer(), returns := non_neg_integer(), retired := non_neg_integer()}.

-doc "Reads at most 128 KiB of trusted simulator terms, requires the explicit footer, checks every edge and returns the artifact with witness counts. File errors and contradictions raise.".
-spec read(file:filename(), hls_spacetime:build()) -> map().
read(Path, Build) ->
    {ok, Bytes} = file:read_file(Path),
    require(byte_size(Bytes) =< 128 * 1024, trace_size),
    {ok, Terms} = file:consult(Path),
    require(length(Terms) >= 2, missing_footer),
    [Footer | ReverseRows] = lists:reverse(Terms),
    bundle(lists:reverse(ReverseRows), Footer, Build).

-doc "Checks complete consecutive samples of the supported two-lane read-first fixture and builds storage histories. Other collision modes, partial-nibble masks and uninitialized reads reject. Reset retires pending requests and starts explicit retained-word roots.".
-spec bundle([row()], footer(), hls_spacetime:build()) -> map().
bundle(Rows, #{end_cycle := End, rows := Count, complete := true,
              collision := read_first}, Build) when Count > 0, Count =< 4096 ->
    require(Count =:= length(Rows) andalso End =:= Count, footer_count),
    require([maps:get(cycle, R) || R <- Rows] =:= lists:seq(0, End - 1), cycle_coverage),
    Initial = #{inc => -1, epoch_start => 0, last_reset => 0, seq => 0,
        events => [], versions => [], epochs => [], words => #{}, pending => #{},
        writes => 0, equal_writes => 0, masked_writes => 0, collisions => 0,
        reads => 0, returns => 0, retired => 0},
    S = lists:foldl(fun sample/2, Initial, Rows),
    #{inc := Inc, epoch_start := Start, epochs := Epochs, seq := Seq,
      events := Events, versions := Versions, pending := Pending} = S,
    require(map_size(Pending) =:= 0, pending_tail),
    Capture = #{device => <<"memory-fixture">>, clock => <<"clk">>, first_cycle => 0,
        end_cycle => End, complete => true,
        evidence => <<"Every pre-edge control, RAM word and registered response sampled by the passive RTL testbench">>,
        incarnations => lists:reverse([epoch(Inc, Start, End) | Epochs]),
        observers => [#{id => <<"ram">>, first_sequence => 0, next_sequence => Seq,
            gaps => [], scope => <<"Both word addresses; every write/read enable, held word and valid response; reset masks operations">>}]},
    Resource = #{id => <<"memory">>, kind => bram, width => 8, depth => 2,
        ports => #{<<"w">> => write, <<"r">> => read}, read_latency => 2,
        collision => read_first, reset => retained,
        evidence => <<"Logical two-lane RTL RAM using hls_1r1w_ram; no native primitive or area claim">>},
    Bundle = #{format => spacetime, schema => 1, unit => cycle,
        evidence => simulation_witness, build => Build, capture => Capture,
        resources => [Resource], versions => lists:reverse(Versions),
        events => lists:reverse(Events), relations => [], activity => [], physical => null},
    Summary = hls_spacetime:validate(Bundle),
    Counts = maps:with([writes, equal_writes, masked_writes, collisions, reads, returns, retired], S),
    #{bundle => Bundle, summary => Summary, witness => Counts};
bundle(_, _, _) ->
    error({spacetime_memory_fixture, unsupported_or_incomplete_capture}).

%% Reset boundaries retire responses; all retained bits are checked rather than cleared.
-spec sample(row(), state()) -> state().
sample(#{cycle := C, reset := Reset, old := Old, new := New} = R, S0) ->
    validate_row(R),
    case maps:get(inc, S0) of
        -1 -> ok;
        _ -> require([maps:get(value, maps:get(A, maps:get(words, S0))) || A <- [0, 1]] =:= Old,
            {between_edge_words, C})
    end,
    S1 = case {maps:get(inc, S0), maps:get(last_reset, S0), Reset} of
        {-1, _, _} -> begin_epoch(C, Old, S0);
        {_, 0, 1} -> begin_epoch(C, Old, S0);
        _ -> S0
    end,
    Words = maps:get(words, S1),
    require([maps:get(value, maps:get(A, Words)) || A <- [0, 1]] =:= Old, {old_words, C}),
    S2 = case Reset of
        1 ->
            require(New =:= Old andalso maps:get(result_valid, R) =:= 0, {reset, C}),
            S1;
        0 ->
            Returned = response(R, S1),
            Requested = request(R, Returned),
            Written = write(R, Requested),
            Held = lists:foldl(fun(A, S) -> hold(R, A, S) end, Written, [0, 1]),
            require([maps:get(value, maps:get(A, maps:get(words, Held))) || A <- [0, 1]] =:= New,
                {new_words, C}),
            Held
    end,
    S2#{last_reset := Reset}.

%% The testbench is a trusted producer, but malformed record shapes still fail closed.
-spec validate_row(row()) -> ok.
validate_row(#{reset := Reset, read_enable := RE, read_address := RA,
    write_enable := WE, write_address := WA, write_data := Data, write_mask := Mask,
    old := [A, B], new := [C, D], result_valid := Valid, result_data := Result}) ->
    require(lists:all(fun(X) -> X =:= 0 orelse X =:= 1 end, [Reset, RE, RA, WE, WA, Valid]), controls),
    require(is_integer(Data) andalso Data >= 0 andalso Data < 256, write_data),
    require(WE =:= 0 orelse lists:member(Mask, [16#0f, 16#f0, 16#ff]), unsupported_mask),
    require(lists:all(fun word/1, [A, B, C, D, Result]), word).

%% Preserve unknown power-on bits without assigning an arbitrary initialization value.
-spec word(term()) -> boolean().
word(unknown) -> true;
word(N) -> is_integer(N) andalso N >= 0 andalso N < 256.

%% A reset creates new roots even if the retained memory bits equal the prior incarnation.
-spec begin_epoch(non_neg_integer(), [word()], state()) -> state().
begin_epoch(C, Values, #{inc := Previous, epoch_start := Start, epochs := Epochs,
    versions := Versions, pending := Pending, retired := Retired} = S) ->
    Inc = Previous + 1,
    Origin = case Previous of -1 -> unknown; _ -> carry_in end,
    Roots = [#{id => root_id(Inc, A), incarnation => incarnation(Inc), producer => root,
        origin => Origin, storage => #{resource => <<"memory">>, address => A},
        evidence => evidence({observed_retained_root, A, lists:nth(A + 1, Values)})} || A <- [0, 1]],
    PriorEpochs = case Previous of -1 -> Epochs; _ -> [epoch(Previous, Start, C) | Epochs] end,
    Words = maps:from_list([{A, #{version => root_id(Inc, A),
        value => lists:nth(A + 1, Values)}} || A <- [0, 1]]),
    S#{inc := Inc, epoch_start := C, epochs := PriorEpochs, words := Words,
        versions := lists:reverse(Roots) ++ Versions, pending := #{}, retired := Retired + map_size(Pending)}.

%% The observed valid response must match exactly one same-incarnation request two clocks earlier.
-spec response(row(), state()) -> state().
response(#{cycle := C, result_valid := Valid, result_data := Data}, #{pending := Pending} = S) ->
    case maps:take(C, Pending) of
        error -> require(Valid =:= 0, {unexpected_response, C}), S;
        {#{event := Request, version := Word, address := A, value := Value}, Rest} ->
            require(Valid =:= 1 andalso Data =:= Value, {response, C, Value, Data}),
            Id = event_id(maps:get(seq, S)),
            ValueId = <<"result-", Id/binary>>,
            E = event(C, <<"read_return">>, [Word], [ValueId], S),
            Access = #{kind => read_result, resource => <<"memory">>, address => A,
                port => <<"r">>, version => Word, request => Request},
            V = version(ValueId, Id, null, evidence({observed_response, Value}), S),
            add(E#{activation := <<"read-", Request/binary>>, access => Access}, [V],
                S#{pending := Rest, returns := maps:get(returns, S) + 1})
    end.

%% Requests select the old word even when this edge also writes the same address.
-spec request(row(), state()) -> state().
request(#{read_enable := 0}, S) -> S;
request(#{cycle := C, read_enable := 1, read_address := A,
    write_enable := WE, write_address := WA}, #{words := Words, pending := Pending} = S) ->
    #{version := Word, value := Value} = maps:get(A, Words),
    require(Value =/= unknown, {uninitialized_read, C, A}),
    E = event(C, <<"read_accept">>, [Word], [], S),
    Id = maps:get(id, E),
    Access = #{kind => read_request, resource => <<"memory">>, address => A,
        port => <<"r">>, version => Word},
    Request = #{event => Id, version => Word, address => A, value => Value},
    Collision = case WE =:= 1 andalso WA =:= A of true -> 1; false -> 0 end,
    add(E#{activation := <<"read-", Id/binary>>, access => Access}, [],
        S#{pending := Pending#{C + 2 => Request}, reads := maps:get(reads, S) + 1,
            collisions := maps:get(collisions, S) + Collision}).

%% Writes are enabled transactions; equal values still get new versions.
-spec write(row(), state()) -> state().
write(#{write_enable := 0}, S) -> S;
write(#{cycle := C, write_enable := 1, write_address := A,
    write_data := Data, write_mask := Mask}, #{words := Words} = S) ->
    #{version := Before, value := Old} = maps:get(A, Words),
    require(Mask =:= 255 orelse Old =/= unknown, {uninitialized_masked_write, C, A}),
    New = case Mask of 255 -> Data; _ -> (Old band (255 bxor Mask)) bor (Data band Mask) end,
    Id = event_id(maps:get(seq, S)),
    After = <<"word-", Id/binary>>,
    Inputs = case Mask of 255 -> []; _ -> [Before] end,
    E = event(C, <<"write">>, Inputs, [After], S),
    Access = #{kind => write, resource => <<"memory">>, address => A, port => <<"w">>,
        before => Before, after_version => After, mask => Mask},
    V = version(After, Id, #{resource => <<"memory">>, address => A},
        evidence({observed_write, Old, New, Mask}), S),
    Equal = case Old =:= New of true -> 1; false -> 0 end,
    Partial = case Mask =/= 255 of true -> 1; false -> 0 end,
    add(E#{access => Access}, [V], S#{words := Words#{A => #{version => After, value => New}},
        writes := maps:get(writes, S) + 1, equal_writes := maps:get(equal_writes, S) + Equal,
        masked_writes := maps:get(masked_writes, S) + Partial}).

%% Disabled word enables retain identity, including clocks that accept reads.
-spec hold(row(), 0 | 1, state()) -> state().
hold(#{write_enable := 1, write_address := A}, A, S) -> S;
hold(#{cycle := C}, A, #{words := Words} = S) ->
    #{version := Word} = maps:get(A, Words),
    E = event(C, <<"hold">>, [Word], [], S),
    Access = #{kind => hold, resource => <<"memory">>, address => A, port => <<"w">>, version => Word},
    add(E#{access => Access}, [], S).

%% Observer sequence orders records; only explicit inputs and requests create dependency edges.
-spec event(non_neg_integer(), binary(), [binary()], [binary()], state()) -> hls_spacetime:event().
event(C, Operation, Inputs, Outputs, #{seq := Seq, inc := Inc}) ->
    Id = event_id(Seq),
    #{id => Id, observer => <<"ram">>, sequence => Seq, cycle => C, incarnation => incarnation(Inc),
        actor => <<"memory-driver">>, task => <<"memory-witness">>, activation => <<"op-", Id/binary>>,
        operation => Operation, inputs => Inputs, outputs => Outputs,
        evidence => <<"Passive pre-edge enable/data sampling and post-edge word check">>}.

%% Append one observation and its produced value versions.
-spec add(hls_spacetime:event(), [hls_spacetime:version()], state()) -> state().
add(E, NewVersions, #{seq := Seq, events := Events, versions := Versions} = S) ->
    S#{seq := Seq + 1, events := [E | Events], versions := lists:reverse(NewVersions) ++ Versions}.

%% Produced values belong to this reset incarnation and exactly one observation.
-spec version(binary(), binary(), null | map(), binary(), state()) -> hls_spacetime:version().
version(Id, Producer, Storage, Evidence, #{inc := Inc}) ->
    #{id => Id, incarnation => incarnation(Inc), producer => Producer, origin => event,
        storage => Storage, evidence => Evidence}.

%% Half-open intervals partition the complete capture.
-spec epoch(non_neg_integer(), non_neg_integer(), pos_integer()) -> map().
epoch(Inc, Start, End) -> #{id => incarnation(Inc), first_cycle => Start, end_cycle => End}.

%% Stable local names do not depend on payload values.
-spec incarnation(non_neg_integer()) -> binary().
incarnation(Inc) -> <<"reset-", (integer_to_binary(Inc))/binary>>.

%% Each root is local to one address and incarnation.
-spec root_id(non_neg_integer(), 0 | 1) -> binary().
root_id(Inc, A) -> <<"root-", (integer_to_binary(Inc))/binary, "-", (integer_to_binary(A))/binary>>.

%% Event numbers are observer sequence numbers, not value hashes.
-spec event_id(non_neg_integer()) -> binary().
event_id(N) -> <<"e-", (integer_to_binary(N))/binary>>.

%% Retain exact observed values in human-readable fixture evidence.
-spec evidence(term()) -> binary().
evidence(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).

%% Contradictions keep the test's failing condition visible.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({spacetime_memory_fixture, Reason}).
