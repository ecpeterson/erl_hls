-module(hls_protocol_transactions).
-moduledoc "Plans immutable source-entry batches with independent recipient delivery and per-sender order. It does not infer slot lifetime or authorize a hardware schedule.".
-export([plan/2]).

-doc "Expands every retained instance entry layout into immutable payload captures and per-recipient sequences. Each logical sender keeps one active transaction until all recipients accept it, so later batches cannot overtake it. Sends to distinct recipients may be delivered independently; sends through different ports to one recipient remain ordered. Runtime layout selection and source failures are unchanged. Inputs must be complete source-bound eligibility and entry-fact reports. This plan leaves destination capacity, boundary contracts and progress unestablished.".
-spec plan(map(), #{term() => [map()]}) -> map().
plan(#{actors := Actors, modules := Modules, channels := Channels}, Entries) ->
    #{actors => [actor(Id, maps:get(entry_layouts,maps:get(M,Modules)), maps:get(Id, Entries), Channels) || #{id := Id,module := M} <- Actors],
      snapshot => evaluate_original_selected_entry_once,
      source_ownership => one_active_transaction_until_all_deliveries,
      distinct_destinations => independent_delivery,
      capacity => unestablished, progress => unestablished, eligible => false}.

%% A phase may choose an empty layout; lack of sends must not manufacture a reservation.
-spec actor(term(), [map()], [map()], [map()]) -> map().
actor(Id, Layouts, Alternatives, Channels) ->
    Keys = lists:usort([{P,L} || #{phase:=P,layout:=L} <- Layouts]),
    true = lists:all(fun(#{phase:=P,layout:=L}) -> lists:member({P,L},Keys) end,Alternatives),
    #{actor => Id, batches => [batch(Id,P,L,
        [E || E=#{phase:=EP,layout:=EL} <- Alternatives, EP=:=P,EL=:=L], Channels)
        || {P,L} <- Keys]}.

%% Logical send order stays in the source descriptor; delivery gets only the necessary pair edges.
-spec batch(term(), atom(), non_neg_integer(), [map()], [map()]) -> map().
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
-spec delivery(term(), map(), [map()]) -> [map()].
delivery(Id,#{order:=Order,port:=Port,tag:=Tag},Channels) ->
    Recipients = [D || #{source:=S,port:=P,tag:=T,destination:=D}<-Channels,
        S=:=Id,P=:=Port,T=:=Tag],
    true = Recipients=/=[],
    true = length(Recipients)=:=length(lists:usort(Recipients)),
    [#{source=>Id,destination=>D,order=>Order,port=>Port,tag=>Tag} || D<-Recipients].

%% Ordinary payload offsets identify shared evaluated bits; constants need no snapshot storage.
-spec capture([map()]) -> map().
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
