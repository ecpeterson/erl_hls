-module(hls_phi_memory_metrics).
-moduledoc "Progress measurements from accepted public application beats in the selected activation.".
-export([write/1, write/2, write/3, status_events/1]).

-doc "Decodes the fresh activation's public events and records complete status-round intervals.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    write(Stage, <<"Accepted application-output complete status intervals after round 8; includes host pacing and periodic link stalls, excludes deliberate fault/debug pauses; not core-only throughput.">>).

-doc "Records status-round intervals with the caller's explicit experiment scope.".
-spec write(file:filename(), binary()) -> ok.
write(Stage, Scope) ->
    write(Stage, Scope, 18).

-doc "Records consecutive intervals from round 8 through the earlier of round 18 and closeout; rejects incomplete or empty windows.".
-spec write(file:filename(), binary(), non_neg_integer()) -> ok.
write(Stage, Scope, Closeout) ->
    {ok, [Partition]} = file:consult(filename:join(Stage, "deployment.term")),
    Sources = length([ok || #{module := phi_halo_cell} <- maps:get(actors, Partition)]),
    Events = status_events(Stage),
    ok = hls_bridge_phi_live:save(Stage, "status-events.json", Events),
    Rounds = lists:foldl(fun(#{stream := Stream, step := Step, x := X, y := Y, time_ns := Time}, Acc) ->
        maps:update_with(Step, fun(M) -> M#{{Stream, X, Y} => Time} end, #{{Stream, X, Y} => Time}, Acc)
    end, #{}, Events),
    %% Require every placed phi actor, including both planes, at each round boundary.
    Complete = [{Step, lists:max(maps:values(Times))} || {Step, Times} <- lists:sort(maps:to_list(Rounds)),
        Step >= 8, Step =< min(18, Closeout), map_size(Times) =:= Sources],
    %% Only the experiment's closeout may shorten the window, not missing samples.
    Last = min(18, Closeout),
    true = Last > 8,
    true = lists:seq(8, Last) =:= [Step || {Step, _} <- Complete],
    Intervals = [T1-T0 || {{_, T0}, {_, T1}} <- lists:zip(lists:droplast(Complete), tl(Complete))],
    Mean = lists:sum(Intervals)/length(Intervals),
    Report = #{scope => Scope, first_round => 8, last_round => Last, sample_count => length(Intervals),
        intervals_ns => Intervals, best_ns => lists:min(Intervals), mean_ns => Mean,
        variance_ns2 => lists:sum([(N-Mean)*(N-Mean) || N <- Intervals])/length(Intervals),
        worst_ns => lists:max(Intervals),
        complete_rounds => [#{step => Step, time_ns => Time} || {Step, Time} <- Complete]},
    hls_bridge_phi_live:save(Stage, "progress.json", Report).

-doc "Returns accepted public status frames with decoded identities and exact payload bytes for causal matching.".
-spec status_events(file:filename()) -> [map()].
status_events(Stage) ->
    {ok, [Partition]} = file:consult(filename:join(Stage, "deployment.term")),
    #{devices := Devices} = hls_partition_binding:deployment(Partition),
    {ok, Data} = file:read_file(filename:join(Stage, "progress.log")),
    Lines = [binary:split(Line, <<" ">>, [global]) || Line <- binary:split(Data, <<"\n">>, [global]), Line =/= <<>>],
    {Events, _Pending} = lists:foldl(fun(Line, Acc) -> beat(Line, Devices, Acc) end, {[], #{}}, Lines),
    [maps:merge(maps:without([event], E), #{step => Step, x => X, y => Y, flags => Flags})
     || E = #{event := {phi_status, Step, X, Y, Flags}} <- lists:reverse(Events)].

%% A partial packet at the discarded activation boundary cannot join the fresh packet stream.
-spec beat([binary()], map(), {[map()], map()}) -> {[map()], map()}.
beat([<<"1">>, D, Cycle, Time, Word, Last], Devices, {Events, Pending}) ->
    Device = binary_to_integer(D),
    Words = [binary_to_integer(Word, 16) | maps:get(Device, Pending, [])],
    case Last of
        <<"0">> -> {Events, Pending#{Device => Words}};
        <<"1">> ->
            Packet = lists:reverse(Words),
            New = event(Packet, maps:get(Device, Devices)),
            {[E#{device => Device, cycle => binary_to_integer(Cycle), time_ns => binary_to_integer(Time)}
                || E <- New] ++ Events, Pending#{Device => []}}
    end;
beat(_, _, Acc) -> Acc.

%% Management acknowledgments delimit frames but are not application status samples.
-spec event([non_neg_integer()], map()) -> [map()].
event([Route, Header | Words], Binding = #{control := Control}) ->
    <<Source:16, Host:16>> = <<Route:32>>,
    <<Op:8, Tx:8, Flags:8, Size:8>> = <<Header:32>>,
    Size = length(Words),
    case Source of
        Control -> [];
        _ ->
            Payload = << <<Word:32/little>> || Word <- Words >>,
            {Stream, Event} = hls_partition_wire:event(Binding, {Source, Host}, {Op, Flags, Tx}, Payload),
            [#{stream => Stream, event => Event, payload_hex => binary:encode_hex(Payload),
               header_word => Header}]
    end.
