-module(hls_protocol_inbox).
-moduledoc "Plans typed capture histories and receiver layouts for source transport. Per-pair precedence preserves selective receive without inventing cross-sender chronology; xls_protocol_inbox consumes the checked layout to attach receiver hardware to an ordinary owner.".

%% Receiver layout planning.
-export([plan/1, plan/5]).

%% Retained layout and binding views.
-export([descriptor/1, completion/1, link_bindings/1]).
-export_type([link_binding/0, plan/0, pair/0, slot/0, receiver_slot/0, layout/0, metadata/0]).

%% Retain source-derived codecs and ownership, never generated hardware text.
-record(layout, {metadata :: metadata(), shared :: boolean()}).

-doc "A checked receiver layout from plan/5, including startup encodings and optional host/completion ports. Retain unchanged alongside its source snapshot.".
-opaque layout() :: #layout{}.

-doc "One capture channel's fixed slot within a logical sender/destination history.".
-type slot() :: #{
    index := non_neg_integer(),
    channel := hls_protocol_capture:binding(),
    payload_bits := non_neg_integer()
}.

-doc "Independent history for one logical sender and destination, with physical capture slots in canonical channel order.".
-type pair() :: #{
    source := term(),
    destination := term(),
    slots := [slot()],
    parameters := #{slots := pos_integer()},
    arrival_contract := one_accepted_message_per_clock_in_sender_order,
    reuse_contract := capture_credit_and_absent_pending_message
}.

-doc "Checked sender-local histories; capacity and network progress remain unestablished.".
-type plan() :: #{
    frame_layout := hls_frame_layout:layout(),
    pairs := [pair()],
    cross_sender_chronology := none,
    selection := oldest_eligible_within_logical_sender,
    postponed_message := retained_without_blocking_later_eligible_message,
    leased_payload := held_separately_until_consumer_release,
    capacity := unestablished,
    network_progress := unestablished,
    eligible := false
}.

-doc "A physical payload slice and its source-derived ordinary-frame codec at one inbox index.".
-type receiver_slot() :: #{
    index := non_neg_integer(),
    link := non_neg_integer(),
    slot := non_neg_integer(),
    width := non_neg_integer(),
    payload_offset := non_neg_integer(),
    codec := hls_protocol_codec:plan()
}.

-doc "Static receiver mask, startup, host and frame-codec layout. Fields describe ownership and bit placement, not hardware timing or application progress.".
-type metadata() :: #{
    frame_layout := hls_frame_layout:layout(),
    physical_slots := non_neg_integer(),
    mask_bits := pos_integer(),
    cursor_bits := pos_integer(),
    additional_state_bits := non_neg_integer(),
    host := #{slots := 0 | 1, offset := non_neg_integer(), retirement := source_consume},
    startup := #{
        count := non_neg_integer(),
        offset := non_neg_integer(),
        frames := [non_neg_integer()],
        order := oldest_eligible_declared_record,
        retirement := source_consume,
        reset := replay
    },
    inputs := [#{name := binary(), width := pos_integer()}],
    slots := [receiver_slot()],
    links := [#{index := non_neg_integer(), slots := pos_integer()}],
    selected_head := pending_until_consumed,
    release := one_clock_after_consume,
    phase_boundary := wakes_all_postponed,
    ordering := per_logical_sender_destination,
    capacity := unestablished,
    network_progress := unestablished
}.

-doc "One incoming link and its contiguous span in the receiver eligibility, take and release masks.".
-type link_binding() :: #{
    index := non_neg_integer(), slots := pos_integer(), offset := non_neg_integer()
}.

-doc "Plans independent sender/destination histories over exact typed capture channels. Channels from distinct ports of one sender share a history; separate senders do not. Each pending channel currently has one slot, so a repeated send must wait for its lease to be released. This establishes neither sufficient application capacity nor transport deadlock freedom; whole-protocol eligibility remains false.".
-spec plan(hls_protocol_capture:plan()) -> plan().
plan(Capture = #{channels := Channels}) ->
    FrameLayout = maps:get(frame_layout, Capture, hls_frame_layout:default()),
    Groups = lists:foldl(
        fun(C = #{source := Source, destination := Destination}, Acc) ->
            maps:update_with({Source, Destination}, fun(Cs) -> [C | Cs] end, [C], Acc)
        end,
        #{},
        Channels
    ),
    #{
        frame_layout => FrameLayout,
        pairs => [pair(Key, Cs) || {Key, Cs} <- lists:sort(maps:to_list(Groups))],
        cross_sender_chronology => none,
        selection => oldest_eligible_within_logical_sender,
        postponed_message => retained_without_blocking_later_eligible_message,
        leased_payload => held_separately_until_consumer_release,
        capacity => unestablished,
        network_progress => unestablished,
        eligible => false
    }.

%% Every physical channel has a stable identity; duplicate routes cannot create alias slots.
-spec pair({term(), term()}, [hls_protocol_capture:channel()]) -> pair().
pair({Source, Destination}, Channels) ->
    Keys = [{maps:get(port, C), maps:get(tag, C)} || C <- Channels],
    case length(Keys) =:= length(lists:usort(Keys)) of
        true -> ok;
        false -> error({duplicate_capture_channel, Source, Destination})
    end,
    Ordered = lists:keysort(1, lists:zip(Keys, Channels)),
    #{
        source => Source,
        destination => Destination,
        slots => [
            #{
                index => I,
                channel => maps:with([source, port, tag, destination], C),
                payload_bits => maps:get(payload_bits, C)
            }
         || {I, {_, C}} <- lists:enumerate(0, Ordered)
        ],
        parameters => #{slots => length(Channels)},
        arrival_contract => one_accepted_message_per_clock_in_sender_order,
        reuse_contract => capture_credit_and_absent_pending_message
    }.

-doc "Checks receiver slots, source startup records, frame codecs and host/completion fields without reading templates or rendering DSLX. Requires the same checked source and capture plan as the incoming links; total capture, startup and host slots must not exceed 256.".
-spec plan(
    hls_local_actor:source() | hls_local_actor:artifact(),
    [hls_protocol_fabric:link()],
    hls_protocol_capture:plan(),
    [tuple()],
    boolean()
) -> layout().
plan(Artifact = #{program := Program}, Links, Capture = #{channels := Channels}, Messages, Host) ->
    #{message_names := Names, frame_layout := FrameLayout} = xls_actor_program:spec(Program),
    FrameLayout = maps:get(frame_layout, Capture, FrameLayout),
    FrameBits = hls_frame_layout:frame_bits(FrameLayout),
    Starts = hls_protocol_schema:frames(Artifact, Messages),
    Rows = lists:append([
        [
            begin
                [Op] = [N || {N, T} <- lists:enumerate(3, Names), T =:= maps:get(tag, C)],
                [Channel] = [
                    Ch
                 || Ch <- Channels, maps:with([source, destination, port, tag], Ch) =:= C
                ],
                #{
                    link => I,
                    slot => K,
                    width => lists:nth(K + 1, Widths),
                    payload_offset => lists:sum(lists:sublist(Widths, K)),
                    codec => hls_protocol_codec_plan:plan(Channel, Op, FrameLayout)
                }
            end
         || #{index := K, channel := C} <- Slots
        ]
     || #{index := I, widths := Widths, pair := #{slots := Slots}} <- Links
    ]),
    Count = length(Rows),
    StartupCount = length(Starts),
    HostCount =
        case Host of
            true -> 1;
            false -> 0
        end,
    Total = Count + StartupCount + HostCount,
    case Total =< 256 of
        true -> ok;
        false -> error({inbox_slot_limit, Total, 256})
    end,
    N = max(1, Total),
    Cursor = max(1, ceil(math:log2(N))),
    Indexed = [R#{index => I} || {I, R} <- lists:enumerate(0, Rows)],
    Shared = maps:get(mode, maps:get(completion, Artifact, #{}), local) =:= shared,
    CompletionFields =
        case Shared of
            false ->
                [];
            true ->
                #{machine_bits := MW} = hls_local_actor:descriptor(Artifact),
                [{"completion_granted", 1}, {"completion_action", MW + 1 + 2 + 1}]
        end,
    Fields =
        [{"reset", 1}, {"output_ready", 1}] ++ CompletionFields ++
            (case Host of
                true -> [{"host_valid", 1}, {"host_frame", FrameBits}];
                false -> []
            end) ++
            lists:append([
                [
                    {link_name(I) ++ "_selected", S},
                    {link_name(I) ++ "_available", S},
                    {link_name(I) ++ "_payloads", W}
                ]
             || #{index := I, slots := S, payload_bits := W} <- Links
            ]),
    #layout{
        shared = Shared,
        metadata = #{
            frame_layout => FrameLayout,
            physical_slots => Count,
            mask_bits => N,
            cursor_bits => Cursor,
            additional_state_bits => 3 * N + Cursor + 1 + StartupCount,
            host => #{
                slots => HostCount, offset => Count + StartupCount, retirement => source_consume
            },
            startup => #{
                count => StartupCount,
                offset => Count,
                frames => Starts,
                order => oldest_eligible_declared_record,
                retirement => source_consume,
                reset => replay
            },
            inputs => [#{name => list_to_binary(K), width => W} || {K, W} <- Fields],
            slots => Indexed,
            links => [maps:with([index, slots], L) || L <- Links],
            selected_head => pending_until_consumed,
            release => one_clock_after_consume,
            phase_boundary => wakes_all_postponed,
            ordering => per_logical_sender_destination,
            capacity => unestablished,
            network_progress => unestablished
        }
    }.

-doc "Returns checked receiver layout metadata without a generated-byte identity. Treat it as read-only; xls_protocol_inbox:attach/2 consumes this exact layout during emission.".
-spec descriptor(layout()) -> metadata().
descriptor(#layout{metadata = Metadata}) -> Metadata.

-doc "Returns whether the checked owner completes scalar work locally or accepts a shared arithmetic grant. This controls its completion ports without reexamining source.".
-spec completion(layout()) -> local | shared.
completion(#layout{shared = false}) -> local;
completion(#layout{shared = true}) -> shared.

-doc "Returns incoming link mask spans from an attached inbox manifest. Checks that link order/counts describe exactly the indexed physical slots; rejects inconsistent layout with invalid_inbox_link_layout. Link identifiers need not be consecutive or numerically ordered. Startup and host slots are outside these spans.".
-spec link_bindings(metadata()) -> [link_binding()].
link_bindings(#{links := Links, slots := Slots, physical_slots := Count}) ->
    {Bindings, Total} = lists:mapfoldl(
        fun(#{index := I, slots := N}, At) ->
            {#{index => I, slots => N, offset => At}, At + N}
        end,
        0,
        Links
    ),
    Expected = lists:append([
        [{At + K, I, K} || K <- lists:seq(0, N - 1)]
     || #{index := I, slots := N, offset := At} <- Bindings
    ]),
    Actual = [{J, I, K} || #{index := J, link := I, slot := K} <- Slots],
    Ids = [I || #{index := I} <- Links],
    case
        Total =:= Count andalso Expected =:= Actual andalso
            length(Ids) =:= length(lists:usort(Ids)) andalso
            lists:all(fun(#{slots := N}) -> N > 0 end, Links)
    of
        true -> Bindings;
        false -> error(invalid_inbox_link_layout)
    end.

%% Numeric names refer to the unchanged fabric link identities.
-spec link_name(non_neg_integer()) -> string().
link_name(I) -> "link_" ++ integer_to_list(I).
