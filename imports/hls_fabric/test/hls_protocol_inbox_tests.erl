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

%% Eligibility spans follow receiver slot order, independent of numeric link identities or payload widths.
-spec link_bindings_follow_receiver_order_test() -> ok.
link_bindings_follow_receiver_order_test() ->
    ?assertEqual([
        #{index => 19, slots => 2, offset => 0},
        #{index => 3, slots => 1, offset => 2},
        #{index => 11, slots => 3, offset => 3}
    ], hls_protocol_inbox:link_bindings(binding_inbox())).

%% Startup and host slots do not allocate any transport eligibility span.
-spec link_bindings_without_links_test() -> ok.
link_bindings_without_links_test() ->
    Inbox = #{links => [], slots => [], physical_slots => 0, mask_bits => 3,
        startup => #{count => 2, offset => 0}, host => #{slots => 1, offset => 2}},
    ?assertEqual([], hls_protocol_inbox:link_bindings(Inbox)).

%% Global slot positions, local positions and link membership must agree with the receiver declaration.
-spec inconsistent_indexed_link_slots_test() -> ok.
inconsistent_indexed_link_slots_test() ->
    Inbox = #{slots := [First, Second | Rest]} = binding_inbox(),
    Invalid = [
        [First#{index := 1}, Second | Rest],
        [Second, First | Rest],
        [First#{slot := 1}, Second | Rest],
        [First#{link := 3}, Second | Rest],
        [First | Rest]
    ],
    lists:foreach(fun(Slots) ->
        ?assertError(invalid_inbox_link_layout,
            hls_protocol_inbox:link_bindings(Inbox#{slots := Slots}))
    end, Invalid).

%% Physical count and link multiplicity cannot diverge from the indexed capture rows.
-spec inconsistent_link_counts_test() -> ok.
inconsistent_link_counts_test() ->
    Inbox = #{links := [First | Rest]} = binding_inbox(),
    Invalid = [
        Inbox#{physical_slots := 5},
        Inbox#{links := [First#{slots := 1} | Rest]},
        #{links => [#{index => 7, slots => 1}, #{index => 7, slots => 1}],
          slots => [#{index => 0, link => 7, slot => 0},
              #{index => 1, link => 7, slot => 0}], physical_slots => 2},
        #{links => [#{index => 7, slots => 0}], slots => [], physical_slots => 0}
    ],
    lists:foreach(fun(Layout) ->
        ?assertError(invalid_inbox_link_layout, hls_protocol_inbox:link_bindings(Layout))
    end, Invalid).

%% Sparse, reordered link identities expose numeric-order assumptions in consumers of inbox masks.
-spec binding_inbox() -> map().
binding_inbox() ->
    #{links => [#{index => 19, slots => 2}, #{index => 3, slots => 1},
            #{index => 11, slots => 3}],
      slots => [#{index => 0, link => 19, slot => 0, width => 3},
            #{index => 1, link => 19, slot => 1, width => 17},
            #{index => 2, link => 3, slot => 0, width => 1},
            #{index => 3, link => 11, slot => 0, width => 8},
            #{index => 4, link => 11, slot => 1, width => 5},
            #{index => 5, link => 11, slot => 2, width => 12}],
      physical_slots => 6, mask_bits => 9,
      startup => #{count => 2, offset => 6}, host => #{slots => 1, offset => 8}}.
