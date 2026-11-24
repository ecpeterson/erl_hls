-module(hls_protocol_capture).
-moduledoc "Derives typed capture fields from complete compiler-owned actor programs for transport preparation. Source, inbox and transaction planners reuse the same layout; capture capacity, receipt eligibility and network progress remain separate obligations.".

%% Source-bound capture layout.
-export([plan/2]).
-export_type([binding/0, field/0, channel/0, plan/0]).

-doc "One declared source port/message class and its logical recipient; no physical link index is assigned yet.".
-type binding() :: #{
    source := hls_logical_topology:id(),
    port := atom(),
    tag := atom(),
    destination := hls_logical_topology:destination(),
    atom() => term()
}.

-doc "A whole source field at its ordinary stream offset. Constants need no capture storage; retained fields have a compact capture offset.".
-type field() ::
    #{
        name := atom(),
        type := hls_type:descriptor(),
        message_bit_offset := non_neg_integer(),
        constant := bitstring()
    }
    | #{
        name := atom(),
        type := hls_type:descriptor(),
        message_bit_offset := non_neg_integer(),
        capture_bit_offset := non_neg_integer()
    }.

-doc "A source-bound internal capture channel, with joined constant fields and exact ordinary/compact widths.".
-type channel() :: #{
    frame_layout := hls_frame_layout:layout(),
    source := hls_logical_topology:id(),
    port := atom(),
    tag := atom(),
    destination := {actor, hls_logical_topology:id()},
    fields := [field()],
    source_operation := 3..((1 bsl 8) - 1),
    message_bits := non_neg_integer(),
    payload_bits := non_neg_integer(),
    parameters := #{width := pos_integer()},
    writer_count := 1,
    reader_count := 1,
    snapshot_slots := 1,
    capacity_bound := unestablished,
    source_alternatives_hash := binary()
}.

-doc "Complete internal capture catalogue and per-producer compiler provenance; temporal admission remains explicitly unestablished.".
-type plan() :: #{
    frame_layout := hls_frame_layout:layout(),
    channels := [channel()],
    sources := #{hls_logical_topology:id() => source_manifest()},
    storage := one_reserved_snapshot_per_static_channel,
    source_ownership := declared_producer_binding,
    overwrite := requires_consumer_release,
    generation_fields := retained_unless_source_constant,
    same_sender_cross_channel_order := requires_publication_and_receive_contract,
    network_progress := unestablished,
    eligible := false
}.

%% The compiler owns the remaining displayed callback and dependency inventory.
-type source_manifest() :: #{
    source := file:filename(),
    source_sha256 := binary(),
    artifact_sha256 := binary(),
    planner_md5 := binary(),
    atom() => term()
}.
%% The joined signature excludes storage metadata belonging to a particular source alternative.
-type signature_field() :: #{name := atom(), type := hls_type:descriptor()}.
%% All alternatives are retained; only their display provenance is projected here.
-type source() :: #{
    alternatives := [xls_actor_program:entry_effect()],
    message_names := [atom()],
    provenance := source_manifest()
}.

-doc "Joins every entry-effect layout across all phases of each internal producer's opaque compiler program. Omits only whole fields constant in every matching send; state-dependent and partially known fields stay whole. Rejects internal retained-call replies, whose destinations require dynamic caller ownership; ordinary entry sends from those actors remain capturable. Programs must come from the same preparation as the actor emitters; no source reads or compilation occur here. Channel bindings are explicit caller input, not validated topology. Supplied alternatives or source/spec maps are not accepted; this does not admit mailbox replacement or network progress.".
-spec plan(
    #{channels := [binding()], atom() => term()},
    #{hls_logical_topology:id() => xls_actor_program:program()}
) -> plan().
plan(#{channels := Channels}, Programs) ->
    FrameLayout = common_layout(Programs),
    Internal = [C || C = #{destination := {actor, _}} <- Channels],
    lists:foreach(
        fun(#{source := Source, port := Port}) ->
            Spec = xls_actor_program:spec(maps:get(Source, Programs)),
            case maps:get(retained_calls, Spec) of
                #{port := Port} -> error({unsupported_capture_replies, maps:get(source, Spec)});
                _ -> ok
            end
        end,
        Internal
    ),
    Producers = lists:usort([S || #{source := S} <- Internal]),
    Sources = maps:from_list([{S, source(maps:get(S, Programs))} || S <- Producers]),
    Rows = [
        begin
            #{alternatives := Entries, message_names := Names} = maps:get(S, Sources),
            Row = channel(C, [E || E = #{port := P, tag := T} <- Entries, P =:= Port, T =:= Tag]),
            [Op] = [N || {N, T} <- lists:enumerate(3, Names), T =:= Tag],
            Row#{frame_layout => FrameLayout, source_operation => Op}
        end
     || C = #{source := S, port := Port, tag := Tag} <- Internal
    ],
    #{
        frame_layout => FrameLayout,
        channels => Rows,
        sources => maps:map(fun(_, #{provenance := P}) -> P end, Sources),
        storage => one_reserved_snapshot_per_static_channel,
        source_ownership => declared_producer_binding,
        overwrite => requires_consumer_release,
        generation_fields => retained_unless_source_constant,
        same_sender_cross_channel_order => requires_publication_and_receive_contract,
        network_progress => unestablished,
        eligible => false
    }.

%% Every native and host actor in one source build shares the same ordinary frame layout.
-spec common_layout(#{hls_logical_topology:id() => xls_actor_program:program()}) ->
    hls_frame_layout:layout().
common_layout(Programs) ->
    case
        lists:usort([
            maps:get(frame_layout, xls_actor_program:spec(Program))
         || Program <- maps:values(Programs)
        ])
    of
        [] -> hls_frame_layout:default();
        [Layout] -> Layout;
        Layouts -> error({inconsistent_frame_layouts, Layouts})
    end.

%% Only the compiler constructor creates programs; there is no selected-alternative input.
-spec source(xls_actor_program:program()) -> source().
source(Program) ->
    #{message_names := Names} = xls_actor_program:spec(Program),
    Alternatives = [
        maps:with([phase, layout, order, port, tag, fields], Effect)
     || Effect <- xls_actor_program:entry_effects(Program)
    ],
    #{
        alternatives => Alternatives,
        message_names => Names,
        provenance => xls_statem_plan:manifest(xls_actor_program:plan(Program))
    }.

%% The complete family determines constants; a convenient single phase cannot stand for all sends.
-spec channel(binding(), [xls_actor_program:entry_effect()]) ->
    #{
        source := hls_logical_topology:id(),
        port := atom(),
        tag := atom(),
        destination := hls_logical_topology:destination(),
        fields := [field()],
        message_bits := non_neg_integer(),
        payload_bits := non_neg_integer(),
        parameters := #{width := pos_integer()},
        writer_count := 1,
        reader_count := 1,
        snapshot_slots := 1,
        capacity_bound := unestablished,
        source_alternatives_hash := binary()
    }.
channel(C, [First | _] = Alternatives) ->
    Signature = [maps:with([name, type], F) || F <- maps:get(fields, First)],
    true = lists:all(
        fun(#{fields := Fs}) -> [maps:with([name, type], F) || F <- Fs] =:= Signature end,
        Alternatives
    ),
    {Fields, {OriginalBits, StoredBits}} = lists:mapfoldl(
        fun(F, {Wire, At}) ->
            Width = hls_type:width(maps:get(type, F)),
            Joined = join(F, Alternatives),
            case Joined of
                #{constant := _} ->
                    {Joined#{message_bit_offset => Wire}, {Wire + Width, At}};
                _ ->
                    {Joined#{message_bit_offset => Wire, capture_bit_offset => At}, {
                        Wire + Width, At + Width
                    }}
            end
        end,
        {0, 0},
        Signature
    ),
    (maps:with([source, port, tag, destination], C))#{
        fields => Fields,
        message_bits => OriginalBits,
        payload_bits => StoredBits,
        parameters => #{width => max(1, StoredBits)},
        writer_count => 1,
        reader_count => 1,
        snapshot_slots => 1,
        capacity_bound => unestablished,
        source_alternatives_hash => hash(Alternatives)
    };
channel(C, []) ->
    error({missing_channel_alternatives, maps:with([source, port, tag, destination], C)}).

%% Partial facts are intentionally retained as full fields until a lossless field codec is qualified.
-spec join(signature_field(), [xls_actor_program:entry_effect()]) ->
    #{name := atom(), type := hls_type:descriptor(), constant => bitstring()}.
join(F = #{name := Name, type := Type}, Alternatives) ->
    Values = [
        maps:find(constant, hd([X || X = #{name := N} <- Fields, N =:= Name]))
     || #{fields := Fields} <- Alternatives
    ],
    case lists:usort(Values) of
        [{ok, Bits}] ->
            true = bit_size(Bits) =:= hls_type:width(Type),
            F#{constant => Bits};
        _ ->
            F
    end.

%% The digest identifies the joined alternatives; it is not an independent correctness certificate.
-spec hash(term()) -> binary().
hash(Term) ->
    binary:encode_hex(crypto:hash(sha256, term_to_binary(Term, [deterministic])), lowercase).
