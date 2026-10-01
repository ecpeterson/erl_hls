-module(hls_indexed_gather).
-moduledoc """
Collects one value per selected numeric member in fixed member order.

A gather captures membership when opened. Its immutable result contains the
membership mask and a capacity-sized list; inactive slots contain the supplied
padding value. Presence is determined by the mask, never by a value's contents.
Empty membership completes immediately. Missing members wait indefinitely.

Only a matching name and key may contribute. The caller decides whether a
mismatched message waits or fails; duplicates and foreign members are errors.
Partial values are private until completion. This is an indexed collection,
with no associativity or commutativity requirement on values or their consumer.
""".
-export([open/5, offer/5, info/1]).
-export_type([gather/1, completion/1, open_error/0, offer_error/0]).

%% Logical reference storage; placement and retained-result leases are separate.
-record(gather, {
    name :: atom(),
    key :: term(),
    capacity :: 1..255,
    expected :: non_neg_integer(),
    seen = 0 :: non_neg_integer(),
    values :: list(),
    remaining :: 1..255
}).

-doc "An incomplete collection whose accepted values cannot be observed yet.".
-opaque gather(Value) :: #gather{values :: [Value]}.
-doc "A complete immutable view in member-index order; bit I describes list element I+1.".
-type completion(Value) :: {gather_complete, atom(), term(), non_neg_integer(), [Value]}.
-doc "An invalid name, capacity or membership mask prevents opening.".
-type open_error() :: invalid_name | invalid_capacity | invalid_members.
-doc "A matching collection rejects duplicate and unselected numeric members.".
-type offer_error() :: {duplicate_member, term()} | {unexpected_member, term()}.

-doc "Opens a bounded gather; an empty mask immediately returns its padded completed view.".
-spec open(atom(), term(), 1..255, non_neg_integer(), Value) ->
    {pending, gather(Value)} | {complete, completion(Value)} | {error, open_error()}.
open(Name, _Key, _Capacity, _Mask, _Padding) when not is_atom(Name) ->
    {error, invalid_name};
open(_Name, _Key, Capacity, _Mask, _Padding)
        when not is_integer(Capacity); Capacity < 1; Capacity > 255 ->
    {error, invalid_capacity};
open(_Name, _Key, Capacity, Mask, _Padding)
        when not is_integer(Mask); Mask < 0; Mask bsr Capacity =/= 0 ->
    {error, invalid_members};
open(Name, Key, Capacity, Mask, Padding) ->
    Values = lists:duplicate(Capacity, Padding),
    case Mask of
        0 -> {complete, {gather_complete, Name, Key, Mask, Values}};
        _ -> {pending, #gather{name = Name, key = Key, capacity = Capacity,
            expected = Mask, values = Values, remaining = population(Mask)}}
    end.

-doc "Accepts one selected member exactly once; a different name or key returns mismatch unchanged.".
-spec offer(atom(), term(), term(), Value, gather(Value)) ->
    mismatch | {pending, gather(Value)} | {complete, completion(Value)} |
    {error, offer_error()}.
offer(Name, Key, _Member, _Value, #gather{name = ExpectedName, key = ExpectedKey})
        when Name =/= ExpectedName; Key =/= ExpectedKey ->
    mismatch;
offer(_Name, _Key, Member, _Value, #gather{capacity = Capacity})
        when not is_integer(Member); Member < 0; Member >= Capacity ->
    {error, {unexpected_member, Member}};
offer(_Name, _Key, Member, Value,
        Gather = #gather{expected = Expected, seen = Seen}) ->
    Bit = 1 bsl Member,
    case {Expected band Bit =/= 0, Seen band Bit =/= 0} of
        {false, _} -> {error, {unexpected_member, Member}};
        {true, true} -> {error, {duplicate_member, Member}};
        {true, false} -> accept(Member, Value, Bit, Gather)
    end.

-doc "Reports membership and progress without exposing unfinished values.".
-spec info(gather(term())) -> #{name := atom(), key := term(), capacity := 1..255,
    expected := non_neg_integer(), seen := non_neg_integer(), remaining := 1..255}.
info(#gather{name = Name, key = Key, capacity = Capacity, expected = Expected,
        seen = Seen, remaining = Remaining}) ->
    #{name => Name, key => Key, capacity => Capacity, expected => Expected,
        seen => Seen, remaining => Remaining}.

%% The last accepted member closes the reference state exactly once for its owner.
-spec accept(non_neg_integer(), Value, pos_integer(), gather(Value)) ->
    {pending, gather(Value)} | {complete, completion(Value)}.
accept(Member, Value, Bit, Gather = #gather{name = Name, key = Key,
        expected = Expected, seen = Seen, remaining = Remaining, values = Values}) ->
    NextValues = replace(Member, Value, Values),
    case Remaining of
        1 -> {complete, {gather_complete, Name, Key, Expected, NextValues}};
        _ -> {pending, Gather#gather{seen = Seen bor Bit,
            remaining = Remaining - 1, values = NextValues}}
    end.

%% Slots are bounded and zero-based at the collection interface.
-spec replace(non_neg_integer(), Value, [Value]) -> [Value].
replace(0, Value, [_ | Tail]) -> [Value | Tail];
replace(Index, Value, [Head | Tail]) -> [Head | replace(Index - 1, Value, Tail)].

%% Membership size is independent of padding values or arrival order.
-spec population(non_neg_integer()) -> non_neg_integer().
population(0) -> 0;
population(Mask) -> 1 + population(Mask band (Mask - 1)).
