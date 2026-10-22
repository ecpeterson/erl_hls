-module(hls_protocol_inbox).
-moduledoc "Groups typed capture channels by logical sender and destination. Per-pair delivery precedence preserves selective receive without inventing cross-sender chronology.".
-export([plan/1]).

-doc "Plans independent sender/destination histories over exact typed capture channels. Channels from distinct ports of one sender share a history; separate senders do not. Each pending channel currently has one slot, so a repeated send must wait for its lease to be released. This establishes neither sufficient application capacity nor transport deadlock freedom; whole-protocol eligibility remains false.".
-spec plan(map()) -> map().
plan(#{channels:=Channels}) ->
    Groups=lists:foldl(fun(C=#{source:=Source,destination:=Destination},Acc)->
        maps:update_with({Source,Destination},fun(Cs)->[C|Cs] end,[C],Acc)
    end,#{},Channels),
    #{pairs=>[pair(Key,Cs)||{Key,Cs}<-lists:sort(maps:to_list(Groups))],
      cross_sender_chronology=>none,selection=>oldest_eligible_within_logical_sender,
      postponed_message=>retained_without_blocking_later_eligible_message,
      leased_payload=>held_separately_until_consumer_release,
      capacity=>unestablished,network_progress=>unestablished,eligible=>false}.

%% Every physical channel has a stable identity; duplicate routes cannot create alias slots.
-spec pair({term(),term()},[map()]) -> map().
pair({Source,Destination},Channels) ->
    Keys=[{maps:get(port,C),maps:get(tag,C)}||C<-Channels],
    case length(Keys)=:=length(lists:usort(Keys)) of
        true->ok;false->error({duplicate_capture_channel,Source,Destination})
    end,
    Ordered=lists:keysort(1,lists:zip(Keys,Channels)),
    #{source=>Source,destination=>Destination,
      slots=>[#{index=>I,channel=>maps:with([source,port,tag,destination],C),
          payload_bits=>maps:get(payload_bits,C)}||{I,{_,C}}<-lists:enumerate(0,Ordered)],
      parameters=>#{slots=>length(Channels)},
      arrival_contract=>one_accepted_message_per_clock_in_sender_order,
      reuse_contract=>capture_credit_and_absent_pending_message}.
