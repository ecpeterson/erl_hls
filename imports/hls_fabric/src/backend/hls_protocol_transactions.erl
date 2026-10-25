-module(hls_protocol_transactions).
-moduledoc "Plans immutable source-entry batches with independent recipient delivery and per-sender order. It does not infer slot lifetime or authorize a hardware schedule.".
-export([plan/2]).
-export_type([delivery/0, batch/0, actor/0, plan/0]).

-doc "One source send delivered to one logical recipient, retaining source order across ports.".
-type delivery() :: #{source := hls_protocol_topology:id(), destination := hls_protocol_topology:destination(),
    order := non_neg_integer(), port := atom(), tag := atom()}.

-doc "One selected entry layout with its shared snapshot, complete sends and independently ordered recipient subsequences.".
-type batch() :: #{phase := atom(), layout := non_neg_integer(), logical_send_order := [non_neg_integer()],
    effects := [effect()], deliveries := [delivery()], per_recipient := [recipient()],
    recipient_count := non_neg_integer(), delivery_count := non_neg_integer(),
    required_pair_sequence_depth := non_neg_integer(), capture := capture(),
    reservation := all_selected_deliveries_before_snapshot_reuse}.

-doc "Every alternative entry transaction for one logical actor, including empty layouts.".
-type actor() :: #{actor := hls_protocol_topology:id(), batches := [batch()]}.

-doc "The complete actor transaction catalogue; independent delivery does not establish capacity or progress.".
-type plan() :: #{actors := [actor()], snapshot := evaluate_original_selected_entry_once,
    source_ownership := one_active_transaction_until_all_deliveries,
    distinct_destinations := independent_delivery, capacity := unestablished,
    progress := unestablished, eligible := false}.

%% Source fields retain their compiler storage metadata without imposing a new representation.
-type effect() :: #{order := non_neg_integer(), port := atom(), tag := atom(), fields := [map()]}.
%% Each recipient sees only its subsequence of the original source send order.
-type recipient() :: #{destination := hls_protocol_topology:destination(),
    effects := [#{order := non_neg_integer(), port := atom(), tag := atom()}]}.
%% Counts price shared evaluated payload bits, not control or routing hardware.
-type capture() :: #{ordinary_payload_ranges := [{non_neg_integer(), non_neg_integer()}],
    distinct_dynamic_bits := non_neg_integer(), constant_field_uses := non_neg_integer(),
    evaluates := original_entry_before_any_delivery, release := after_every_selected_recipient_accepts,
    storage_cost_scope := payload_bits_only_no_control_routing_or_packing}.
%% Planning uses only layout identities from the inventory, not its display-only field projection.
-type inventory() :: #{actors := [#{id := hls_protocol_topology:id(), module := module(), atom() => term()}],
    modules := #{module() => #{entry_layouts := [layout()], atom() => term()}},
    channels := [hls_protocol_capture:binding()], atom() => term()}.
%% Layout identities include empty alternatives omitted from the send list.
-type layout() :: #{phase := atom(), layout := non_neg_integer()}.

-doc "Expands every retained instance entry layout into immutable payload captures and per-recipient sequences. Each logical sender keeps one active transaction until all recipients accept it, so later batches cannot overtake it. Sends to distinct recipients may be delivered independently; sends through different ports to one recipient remain ordered. Runtime layout selection and source failures are unchanged. Inputs must be complete source-bound eligibility and entry-fact reports. This plan leaves destination capacity, boundary contracts and progress unestablished.".
-spec plan(inventory(), #{hls_protocol_topology:id() => [xls_actor_program:entry_effect()]}) -> plan().
plan(#{actors := Actors, modules := Modules, channels := Channels}, Entries) ->
    #{actors => [actor(Id, maps:get(entry_layouts,maps:get(M,Modules)), maps:get(Id, Entries), Channels) || #{id := Id,module := M} <- Actors],
      snapshot => evaluate_original_selected_entry_once,
      source_ownership => one_active_transaction_until_all_deliveries,
      distinct_destinations => independent_delivery,
      capacity => unestablished, progress => unestablished, eligible => false}.

%% A phase may choose an empty layout; lack of sends must not manufacture a reservation.
-spec actor(hls_protocol_topology:id(), [layout()], [xls_actor_program:entry_effect()],
    [hls_protocol_capture:binding()]) -> actor().
actor(Id, Layouts, Alternatives, Channels) ->
    Keys = lists:usort([{P,L} || #{phase:=P,layout:=L} <- Layouts]),
    true = lists:all(fun(#{phase:=P,layout:=L}) -> lists:member({P,L},Keys) end,Alternatives),
    #{actor => Id, batches => [batch(Id,P,L,
        [E || E=#{phase:=EP,layout:=EL} <- Alternatives, EP=:=P,EL=:=L], Channels)
        || {P,L} <- Keys]}.

%% Logical send order stays in the source descriptor; delivery gets only the necessary pair edges.
-spec batch(hls_protocol_topology:id(), atom(), non_neg_integer(),
    [xls_actor_program:entry_effect()], [hls_protocol_capture:binding()]) -> batch().
batch(Id, Phase, Layout, Effects, Channels) ->
    Ordered = [E || {_,E} <- lists:keysort(1,[{maps:get(order,E),E} || E <- Effects])],
    Indices = [I || #{order:=I} <- Ordered],
    true = length(Indices)=:=length(lists:usort(Indices)),
    Deliveries = lists:append([delivery(Id,E,Channels) || E <- Ordered]),
    Destinations = lists:usort([D || #{destination:=D} <- Deliveries]),
    Sequences = [#{destination=>D, effects=>[maps:with([order,port,tag],E)
        || E=#{destination:=ED} <- Deliveries,ED=:=D]} || D <- Destinations],
    #{phase=>Phase,layout=>Layout,logical_send_order=>Indices,
      effects=>[maps:with([order,port,tag,fields],E) || E <- Ordered],
      deliveries=>Deliveries,per_recipient=>Sequences,
      recipient_count=>length(Destinations),delivery_count=>length(Deliveries),
      required_pair_sequence_depth=>lists:max([0|[length(S)||#{effects:=S}<-Sequences]]),
      capture=>capture(Ordered),reservation=>all_selected_deliveries_before_snapshot_reuse}.

%% An absent or duplicate channel is an incomplete contract, never an omitted source send.
-spec delivery(hls_protocol_topology:id(), xls_actor_program:entry_effect(),
    [hls_protocol_capture:binding()]) -> [delivery()].
delivery(Id,#{order:=Order,port:=Port,tag:=Tag},Channels) ->
    Recipients = [D || #{source:=S,port:=P,tag:=T,destination:=D}<-Channels,
        S=:=Id,P=:=Port,T=:=Tag],
    true = Recipients=/=[],
    true = length(Recipients)=:=length(lists:usort(Recipients)),
    [#{source=>Id,destination=>D,order=>Order,port=>Port,tag=>Tag} || D<-Recipients].

%% Ordinary payload offsets identify shared evaluated bits; constants need no snapshot storage.
-spec capture([xls_actor_program:entry_effect()]) -> capture().
capture(Effects) ->
    Fields = lists:append([Fs || #{fields:=Fs} <- Effects]),
    Ranges = lists:usort([range(F) || F <- Fields, not maps:is_key(constant,F)]),
    Bits = lists:usort(lists:append([lists:seq(Start,Start+Width-1) || {Start,Width}<-Ranges])),
    #{ordinary_payload_ranges=>Ranges,distinct_dynamic_bits=>length(Bits),
      constant_field_uses=>length([F || F<-Fields,maps:is_key(constant,F)]),
      evaluates=>original_entry_before_any_delivery,
      release=>after_every_selected_recipient_accepts,
      storage_cost_scope=>payload_bits_only_no_control_routing_or_packing}.

%% Partial constants store only the ordinary codec's unknown slices, not the full field width.
-spec range(map()) -> {non_neg_integer(), non_neg_integer()}.
range(#{offset:=Offset,slices:=Slices}) -> {Offset,lists:sum([W || {_,W}<-Slices])};
range(#{offset:=Offset,type:=Type}) -> {Offset,hls_type:width(Type)}.
