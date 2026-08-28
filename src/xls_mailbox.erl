-module(xls_mailbox).
-moduledoc """
A bounded, associative mailbox semantic model.

Capacity is reserved before a message is committed.  Committing assigns the
message's arrival age, and selection follows Erlang receive ordering: the
oldest committed message matching any clause wins, then the first matching
clause wins for that message.  Selection does not remove a message; `consume/2`
does so and returns its capacity.

Reservations and selections are scoped to both a mailbox identity and a
generation.  `reset/1` advances the generation and invalidates all earlier
contents and tokens.  Reservations also retain an owner chosen by the
transport, allowing `cancel_owner/2` to reclaim incomplete messages when a
sender or link fails without deleting messages which were already committed.
The surrounding transport is responsible for preserving per-source send
order; this structure records the cross-source merge order at commit.
""".

-export([
    new/1,
    new/2,
    reset/1,
    reserve/3,
    cancel/2,
    cancel_owner/2,
    commit/3,
    select/2,
    consume/2,
    info/1
]).

-export_type([
    mailbox/0,
    reservation/0,
    selection/0,
    clause/0
]).

-record(slot, {
    status :: reserved | committed,
    owner :: term(),
    generation :: non_neg_integer(),
    ticket :: non_neg_integer(),
    arrival = undefined :: undefined | non_neg_integer(),
    message = undefined :: term()
}).

-record(mailbox, {
    id :: reference(),
    capacity :: pos_integer(),
    generation :: non_neg_integer(),
    next_ticket = 0 :: non_neg_integer(),
    next_arrival = 0 :: non_neg_integer(),
    slots = #{} :: #{non_neg_integer() => #slot{}}
}).

-record(reservation, {
    mailbox_id :: reference(),
    owner :: term(),
    generation :: non_neg_integer(),
    slot :: non_neg_integer(),
    ticket :: non_neg_integer()
}).

-record(selection, {
    mailbox_id :: reference(),
    generation :: non_neg_integer(),
    slot :: non_neg_integer(),
    ticket :: non_neg_integer(),
    arrival :: non_neg_integer()
}).

-opaque mailbox() :: #mailbox{}.
-opaque reservation() :: #reservation{}.
-opaque selection() :: #selection{}.
-type clause() :: fun((term()) -> boolean()).

-type stale_generation() :: {
    stale_generation,
    Expected :: non_neg_integer(),
    Received :: non_neg_integer()
}.
-type operation_error() ::
    full |
    already_committed |
    invalid_reservation |
    stale_selection |
    stale_generation().

-spec new(pos_integer()) -> mailbox().
new(Capacity) ->
    new(Capacity, 0).

-spec new(pos_integer(), non_neg_integer()) -> mailbox().
new(Capacity, Generation)
        when is_integer(Capacity), Capacity > 0,
             is_integer(Generation), Generation >= 0 ->
    checked(#mailbox{
        id = make_ref(),
        capacity = Capacity,
        generation = Generation
    });
new(_Capacity, _Generation) ->
    error(badarg).

-doc "Advances the incarnation generation and invalidates all resident state.".
-spec reset(mailbox()) -> mailbox().
reset(Mailbox0) ->
    Mailbox = checked(Mailbox0),
    checked(#mailbox{
        id = Mailbox#mailbox.id,
        capacity = Mailbox#mailbox.capacity,
        generation = Mailbox#mailbox.generation + 1
    }).

-doc "Reserves one mailbox slot for a message addressed to `Generation`.".
-spec reserve(non_neg_integer(), term(), mailbox()) ->
    {ok, reservation(), mailbox()} |
    {error, full | stale_generation(), mailbox()}.
reserve(Generation, Owner, Mailbox0)
        when is_integer(Generation), Generation >= 0 ->
    Mailbox = checked(Mailbox0),
    CurrentGeneration = Mailbox#mailbox.generation,
    case Generation of
        CurrentGeneration ->
            reserve_current(Mailbox, Owner);
        _ ->
            {error,
                {stale_generation, CurrentGeneration, Generation},
                Mailbox}
    end;
reserve(_Generation, _Owner, Mailbox0) ->
    _ = checked(Mailbox0),
    error(badarg).

-doc "Cancels a live reservation and releases its slot before commit.".
-spec cancel(reservation(), mailbox()) ->
    {ok, mailbox()} |
    {error, invalid_reservation | stale_generation(), mailbox()}.
cancel(Reservation = #reservation{}, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    case reservation_generation(Reservation, Mailbox) of
        ok ->
            cancel_current(Mailbox, Reservation);
        Error ->
            {error, Error, Mailbox}
    end;
cancel(_Reservation, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    {error, invalid_reservation, Mailbox}.

-doc "Releases every incomplete reservation belonging to `Owner`.".
-spec cancel_owner(term(), mailbox()) -> {non_neg_integer(), mailbox()}.
cancel_owner(Owner, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    Slots = Mailbox#mailbox.slots,
    Retained = maps:filter(
        fun
            (_SlotNumber, #slot{status = reserved, owner = SlotOwner}) ->
                SlotOwner =/= Owner;
            (_SlotNumber, #slot{status = committed}) ->
                true
        end,
        Slots
    ),
    Canceled = map_size(Slots) - map_size(Retained),
    {Canceled, checked(Mailbox#mailbox{slots = Retained})}.

-doc "Commits a complete message into a previously reserved slot.".
-spec commit(reservation(), term(), mailbox()) ->
    {ok, mailbox()} | {error, operation_error(), mailbox()}.
commit(Reservation = #reservation{}, Message, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    case reservation_generation(Reservation, Mailbox) of
        ok ->
            commit_current(Mailbox, Reservation, Message);
        Error ->
            {error, Error, Mailbox}
    end;
commit(_Reservation, _Message, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    {error, invalid_reservation, Mailbox}.

-doc """
Selects without consuming.  The oldest matching message wins; `ClauseIndex` is
one-based and identifies the first predicate that accepted that message.
Clause predicates are required to be pure because skipped messages may be
tested again after each state transition.
""".
-spec select([clause()], mailbox()) ->
    none | {ok, selection(), pos_integer(), term()}.
select(Clauses, Mailbox0) when is_list(Clauses) ->
    Mailbox = checked(Mailbox0),
    ok = validate_clauses(Clauses),
    select_committed(
        committed_by_arrival(Mailbox),
        Clauses,
        Mailbox#mailbox.id,
        Mailbox#mailbox.generation
    );
select(_Clauses, Mailbox0) ->
    _ = checked(Mailbox0),
    error(badarg).

-doc "Consumes a selected message and releases its occupied slot.".
-spec consume(selection(), mailbox()) ->
    {ok, term(), mailbox()} | {error, operation_error(), mailbox()}.
consume(Selection = #selection{}, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    case Selection#selection.mailbox_id of
        MailboxId when MailboxId =:= Mailbox#mailbox.id ->
            CurrentGeneration = Mailbox#mailbox.generation,
            case Selection#selection.generation of
                CurrentGeneration ->
                    consume_current(Mailbox, Selection);
                ReceivedGeneration ->
                    {error,
                        {stale_generation,
                            CurrentGeneration, ReceivedGeneration},
                        Mailbox}
            end;
        _ForeignMailboxId ->
            {error, stale_selection, Mailbox}
    end;
consume(_Selection, Mailbox0) ->
    Mailbox = checked(Mailbox0),
    {error, stale_selection, Mailbox}.

-doc "Returns capacity, generation, and occupancy counters.".
-spec info(mailbox()) -> map().
info(Mailbox0) ->
    Mailbox = checked(Mailbox0),
    Slots = maps:values(Mailbox#mailbox.slots),
    Reserved = length([
        reserved || #slot{status = reserved} <- Slots
    ]),
    Committed = length([
        committed || #slot{status = committed} <- Slots
    ]),
    Occupied = Reserved + Committed,
    #{
        capacity => Mailbox#mailbox.capacity,
        generation => Mailbox#mailbox.generation,
        occupied => Occupied,
        reserved => Reserved,
        committed => Committed,
        available => Mailbox#mailbox.capacity - Occupied
    }.

reserve_current(Mailbox = #mailbox{capacity = Capacity, slots = Slots}, _Owner)
        when map_size(Slots) >= Capacity ->
    {error, full, Mailbox};
reserve_current(Mailbox = #mailbox{
    id = MailboxId,
    capacity = Capacity,
    generation = Generation,
    next_ticket = Ticket,
    slots = Slots
}, Owner) ->
    SlotNumber = first_free_slot(0, Capacity, Slots),
    Slot = #slot{
        status = reserved,
        owner = Owner,
        generation = Generation,
        ticket = Ticket
    },
    NewMailbox = checked(Mailbox#mailbox{
        next_ticket = Ticket + 1,
        slots = Slots#{SlotNumber => Slot}
    }),
    Reservation = #reservation{
        mailbox_id = MailboxId,
        owner = Owner,
        generation = Generation,
        slot = SlotNumber,
        ticket = Ticket
    },
    {ok, Reservation, NewMailbox}.

reservation_generation(
    #reservation{mailbox_id = MailboxId, generation = Generation},
    #mailbox{id = MailboxId, generation = Generation}
) ->
    ok;
reservation_generation(
    #reservation{mailbox_id = MailboxId, generation = Received},
    #mailbox{id = MailboxId, generation = Expected}
) ->
    {stale_generation, Expected, Received};
reservation_generation(#reservation{}, #mailbox{}) ->
    invalid_reservation.

cancel_current(
    Mailbox = #mailbox{slots = Slots},
    #reservation{owner = Owner, slot = SlotNumber, ticket = Ticket}
) ->
    case maps:find(SlotNumber, Slots) of
        {ok, #slot{
            status = reserved,
            owner = Owner,
            ticket = Ticket
        }} ->
            NewMailbox = checked(Mailbox#mailbox{
                slots = maps:remove(SlotNumber, Slots)
            }),
            {ok, NewMailbox};
        _ ->
            {error, invalid_reservation, Mailbox}
    end.

commit_current(
    Mailbox = #mailbox{next_arrival = Arrival, slots = Slots},
    #reservation{owner = Owner, slot = SlotNumber, ticket = Ticket},
    Message
) ->
    case maps:find(SlotNumber, Slots) of
        {ok, #slot{
            status = reserved,
            owner = Owner,
            ticket = Ticket
        } = Slot} ->
            CommittedSlot = Slot#slot{
                status = committed,
                arrival = Arrival,
                message = Message
            },
            NewMailbox = checked(Mailbox#mailbox{
                next_arrival = Arrival + 1,
                slots = Slots#{SlotNumber => CommittedSlot}
            }),
            {ok, NewMailbox};
        {ok, #slot{status = committed, ticket = Ticket}} ->
            {error, already_committed, Mailbox};
        _ ->
            {error, invalid_reservation, Mailbox}
    end.

committed_by_arrival(#mailbox{slots = Slots}) ->
    lists:keysort(1, [
        {Arrival, SlotNumber, Slot}
        || {SlotNumber, Slot = #slot{
                status = committed,
                arrival = Arrival
            }} <- maps:to_list(Slots)
    ]).

select_committed([], _Clauses, _MailboxId, _Generation) ->
    none;
select_committed(
    [{Arrival, SlotNumber, #slot{ticket = Ticket, message = Message}} | Rest],
    Clauses,
    MailboxId,
    Generation
) ->
    case first_matching_clause(Message, Clauses, 1) of
        none ->
            select_committed(Rest, Clauses, MailboxId, Generation);
        ClauseIndex ->
            Selection = #selection{
                mailbox_id = MailboxId,
                generation = Generation,
                slot = SlotNumber,
                ticket = Ticket,
                arrival = Arrival
            },
            {ok, Selection, ClauseIndex, Message}
    end.

first_matching_clause(_Message, [], _Index) ->
    none;
first_matching_clause(Message, [Clause | Rest], Index) ->
    case Clause(Message) of
        true -> Index;
        false -> first_matching_clause(Message, Rest, Index + 1);
        Result -> error({invalid_mailbox_clause_result, Index, Result})
    end.

consume_current(
    Mailbox = #mailbox{slots = Slots},
    #selection{
        slot = SlotNumber,
        ticket = Ticket,
        arrival = Arrival
    }
) ->
    case maps:find(SlotNumber, Slots) of
        {ok, #slot{
            status = committed,
            ticket = Ticket,
            arrival = Arrival,
            message = Message
        }} ->
            NewMailbox = checked(Mailbox#mailbox{
                slots = maps:remove(SlotNumber, Slots)
            }),
            {ok, Message, NewMailbox};
        _ ->
            {error, stale_selection, Mailbox}
    end.

first_free_slot(Index, Capacity, Slots) when Index < Capacity ->
    case maps:is_key(Index, Slots) of
        true -> first_free_slot(Index + 1, Capacity, Slots);
        false -> Index
    end.

validate_clauses(Clauses) ->
    case lists:all(fun(Clause) -> is_function(Clause, 1) end, Clauses) of
        true -> ok;
        false -> error(badarg)
    end.

checked(Mailbox = #mailbox{}) ->
    case mailbox_invariant(Mailbox) of
        ok -> Mailbox;
        {error, Reason} -> error({invalid_mailbox, Reason})
    end;
checked(_Mailbox) ->
    error({invalid_mailbox, invalid_state}).

mailbox_invariant(Mailbox = #mailbox{
    id = MailboxId,
    capacity = Capacity,
    generation = Generation,
    next_ticket = NextTicket,
    next_arrival = NextArrival,
    slots = Slots
}) ->
    Conditions = [
        {invalid_mailbox_id, is_reference(MailboxId)},
        {invalid_capacity, is_integer(Capacity) andalso Capacity > 0},
        {invalid_generation,
            is_integer(Generation) andalso Generation >= 0},
        {invalid_next_ticket,
            is_integer(NextTicket) andalso NextTicket >= 0},
        {invalid_next_arrival,
            is_integer(NextArrival) andalso NextArrival >= 0},
        {invalid_slots, is_map(Slots)},
        {capacity_exceeded,
            is_map(Slots) andalso map_size(Slots) =< Capacity}
    ],
    case first_failed_condition(Conditions) of
        none -> slots_invariant(Mailbox, maps:to_list(Slots));
        Reason -> {error, Reason}
    end.

slots_invariant(Mailbox, SlotPairs) ->
    case first_invalid_slot(Mailbox, SlotPairs) of
        none -> unique_slot_metadata(SlotPairs);
        Reason -> {error, Reason}
    end.

first_invalid_slot(_Mailbox, []) ->
    none;
first_invalid_slot(
    Mailbox = #mailbox{capacity = Capacity, generation = Generation,
        next_ticket = NextTicket, next_arrival = NextArrival},
    [{SlotNumber, Slot} | Rest]
) ->
    Valid =
        is_integer(SlotNumber) andalso
        SlotNumber >= 0 andalso SlotNumber < Capacity andalso
        is_record(Slot, slot) andalso
        Slot#slot.generation =:= Generation andalso
        is_integer(Slot#slot.ticket) andalso
        Slot#slot.ticket >= 0 andalso Slot#slot.ticket < NextTicket andalso
        valid_slot_payload(Slot, NextArrival),
    case Valid of
        true -> first_invalid_slot(Mailbox, Rest);
        false -> {invalid_slot, SlotNumber}
    end.

valid_slot_payload(
    #slot{status = reserved, arrival = undefined, message = undefined},
    _NextArrival
) ->
    true;
valid_slot_payload(
    #slot{status = committed, arrival = Arrival},
    NextArrival
) ->
    is_integer(Arrival) andalso Arrival >= 0 andalso Arrival < NextArrival;
valid_slot_payload(_Slot, _NextArrival) ->
    false.

unique_slot_metadata(SlotPairs) ->
    Tickets = [Slot#slot.ticket || {_SlotNumber, Slot} <- SlotPairs],
    Arrivals = [
        Arrival
        || {_SlotNumber, #slot{status = committed, arrival = Arrival}} <- SlotPairs
    ],
    case length(Tickets) =:= length(lists:usort(Tickets)) of
        false -> {error, duplicate_ticket};
        true ->
            case length(Arrivals) =:= length(lists:usort(Arrivals)) of
                true -> ok;
                false -> {error, duplicate_arrival}
            end
    end.

first_failed_condition([]) ->
    none;
first_failed_condition([{_Reason, true} | Rest]) ->
    first_failed_condition(Rest);
first_failed_condition([{Reason, false} | _Rest]) ->
    Reason.
