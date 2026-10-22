-module(hls_protocol_inbox_tests).
-include_lib("eunit/include/eunit.hrl").

%% Two output ports are still one Erlang sender and require one shared pair history.
-spec ports_are_not_senders_test() -> ok.
ports_are_not_senders_test() ->
    #{pairs:=[#{parameters:=#{slots:=2}}]}=plan([channel(a,p,b),channel(a,q,b)]),ok.

%% Unrelated actors share neither age bits nor an imposed inbox chronology.
-spec different_senders_test() -> ok.
different_senders_test() ->
    #{pairs:=Pairs,cross_sender_chronology:=none}=plan([channel(a,p,c),channel(b,p,c)]),
    ?assertEqual([1,1],[N||#{parameters:=#{slots:=N}}<-Pairs]).

%% The same sender can deliver to independent destinations without imposing their relative progress.
-spec independent_destinations_test() -> ok.
independent_destinations_test() ->
    #{pairs:=Pairs}=plan([channel(a,p,b),channel(a,q,c)]),?assertEqual(2,length(Pairs)).

%% Duplicate topology bindings must not be silently assigned two physical slots.
-spec duplicate_channel_test() -> ok.
duplicate_channel_test() ->
    C=channel(a,p,b),?assertError({duplicate_capture_channel,a,{actor,b}},plan([C,C])).

%% A finite catalogue is not evidence that source transitions cannot overfill it or deadlock.
-spec eligibility_stays_open_test() -> ok.
eligibility_stays_open_test() ->
    #{eligible:=false,capacity:=unestablished,network_progress:=unestablished}=plan([channel(a,p,b)]),ok.

%% Static channel identities match the capture planner's public shape.
-spec channel(atom(),atom(),atom()) -> map().
channel(Source,Port,Destination) -> #{source=>Source,port=>Port,tag=>message,destination=>{actor,Destination},payload_bits=>17}.

%% Tests exercise the public source-topology planner rather than a separate grouping model.
-spec plan([map()]) -> map().
plan(Channels) -> hls_protocol_inbox:plan(#{channels=>Channels}).

%% The eight-bit class identifier reserves 255 as the largest supported count.
-spec excessive_link_classes_test() -> ok.
excessive_link_classes_test() ->
    Slots = [#{index => I, payload_bits => 1} || I <- lists:seq(0,255)],
    ?assertException(error, _, hls_protocol_link:components(#{pairs => [#{slots => Slots}]})),
    [#{widths := Widths}] = hls_protocol_link:components(#{pairs => [#{slots => tl(Slots)}]}),
    ?assertEqual(255, length(Widths)).
