-module(xls_mailbox).
-moduledoc """
A bounded, associative mailbox semantic model.

This module is a state value owned by a trusted process runtime, not a server
and not an API for remote senders.  `xls_statem` provides a CPU-side controller
which keeps it alongside callback data.  Peers ask the transport to deliver a
message rather than calling these functions themselves; the controller
performs the corresponding mailbox operations.  Like the event queue which
lets `gen_statem` postpone events, this arrangement depends on translated user
code not bypassing the controller with a low-level `receive`.  It is
deliberately not part of `xls_gs`: that runtime retains direct
`gen_server`-style dispatch and does not provide selective receive.  The module
is the CPU reference semantics for a future bounded FPGA mailbox
implementation.

Reservation is the serialized admission point.  It consumes capacity before
the transport accepts or assembles a complete message.  Once separate slots
have been reserved, multiple physical ingresses may fill them concurrently.
Commit publishes a completed message and assigns its arrival age; commits are
arbitrated into one observable order.  The surrounding transport must preserve
send order within each source, while commit records the otherwise
nondeterministic merge order between sources.

Selection follows Erlang receive ordering: the oldest committed message
matching any clause wins, then the first matching clause wins for that message.
Selection does not remove a message; `consume/2` does so and returns its
capacity.

`generation` denotes the incarnation of the logical actor at a stable fabric
address.  Resetting or respawning that actor advances the generation so that
late message fragments, reservations, and selections from its previous life
cannot affect the new one.  A controller rebuilding the mailbox after a
respawn seeds the new incarnation with `new/2`; `reset/1` performs the same
transition in place.  The CPU-local mailbox identity additionally prevents a
token from one mailbox value being used against another, even when both have
the same generation.  This reference model treats the generation as unbounded;
a finite fabric encoding will need an explicit rollover and quiescence policy.

Reservations retain a reservation owner chosen by the controller.  This is an
ingress or link failure domain, not the process which owns the mailbox and not
necessarily the remote sender.  `cancel_owner/2` can therefore reclaim its
incomplete messages when it fails without deleting messages which were already
committed.
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
    reservation_owner :: term(),
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
    reservation_owner :: term(),
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

-doc "Creates an empty mailbox for generation zero.".
-spec new(pos_integer()) -> mailbox().
new(Capacity) ->
    new(Capacity, 0).

-doc """
Creates an empty mailbox for an actor incarnation already identified by
`Generation`.  A supervisor can use this form when reconstructing a logical
actor at the same fabric address after a reset or respawn.
""".
-spec new(pos_integer(), non_neg_integer()) -> mailbox().
new(Capacity, Generation)
        when is_integer(Capacity), Capacity > 0,
             is_integer(Generation), Generation >= 0 ->
    #mailbox{
        id = make_ref(),
        capacity = Capacity,
        generation = Generation
    };
new(_Capacity, _Generation) ->
    error(badarg).

-doc """
Advances the logical actor incarnation and invalidates all resident messages
and outstanding tokens.
""".
-spec reset(mailbox()) -> mailbox().
reset(Mailbox = #mailbox{}) ->
    #mailbox{
        id = Mailbox#mailbox.id,
        capacity = Mailbox#mailbox.capacity,
        generation = Mailbox#mailbox.generation + 1
    }.

-doc """
Reserves capacity for a message addressed to `Generation`.  The trusted
mailbox controller calls this before allowing an ingress to assemble or accept
the message body.
""".
-spec reserve(non_neg_integer(), term(), mailbox()) ->
    {ok, reservation(), mailbox()} |
    {error, full | stale_generation(), mailbox()}.
reserve(Generation, ReservationOwner, Mailbox = #mailbox{})
        when is_integer(Generation), Generation >= 0 ->
    CurrentGeneration = Mailbox#mailbox.generation,
    case Generation of
        CurrentGeneration ->
            reserve_current(Mailbox, ReservationOwner);
        _ ->
            {error,
                {stale_generation, CurrentGeneration, Generation},
                Mailbox}
    end;
reserve(_Generation, _ReservationOwner, #mailbox{}) ->
    error(badarg).

-doc "Cancels a live reservation and releases its slot before commit.".
-spec cancel(reservation(), mailbox()) ->
    {ok, mailbox()} |
    {error, invalid_reservation | stale_generation(), mailbox()}.
cancel(Reservation = #reservation{}, Mailbox = #mailbox{}) ->
    case reservation_generation(Reservation, Mailbox) of
        ok ->
            cancel_current(Mailbox, Reservation);
        Error ->
            {error, Error, Mailbox}
    end;
cancel(_Reservation, Mailbox = #mailbox{}) ->
    {error, invalid_reservation, Mailbox}.

-doc """
Releases every incomplete reservation belonging to `ReservationOwner` without
removing any message which that ingress has already committed.
""".
-spec cancel_owner(term(), mailbox()) -> {non_neg_integer(), mailbox()}.
cancel_owner(ReservationOwner, Mailbox = #mailbox{}) ->
    Slots = Mailbox#mailbox.slots,
    Retained = maps:filter(
        fun
            (_SlotNumber, #slot{status = committed}) ->
                true;
            (_SlotNumber, #slot{
                status = reserved,
                reservation_owner = SlotOwner
            }) ->
                SlotOwner =/= ReservationOwner
        end,
        Slots
    ),
    Canceled = map_size(Slots) - map_size(Retained),
    {Canceled, Mailbox#mailbox{slots = Retained}}.

-doc """
Publishes a complete message in a previously reserved slot.  Commit assigns
the message's position in the cross-source arrival order.
""".
-spec commit(reservation(), term(), mailbox()) ->
    {ok, mailbox()} | {error, operation_error(), mailbox()}.
commit(Reservation = #reservation{}, Message, Mailbox = #mailbox{}) ->
    case reservation_generation(Reservation, Mailbox) of
        ok ->
            commit_current(Mailbox, Reservation, Message);
        Error ->
            {error, Error, Mailbox}
    end;
commit(_Reservation, _Message, Mailbox = #mailbox{}) ->
    {error, invalid_reservation, Mailbox}.

-doc """
Selects without consuming.  The oldest matching message wins; `ClauseIndex` is
one-based and identifies the first predicate that accepted that message.
Clause predicates are required to be pure because skipped messages may be
tested again after each state transition.
""".
-spec select([clause()], mailbox()) ->
    none | {ok, selection(), pos_integer(), term()}.
select(Clauses, Mailbox = #mailbox{}) when is_list(Clauses) ->
    ok = validate_clauses(Clauses),
    select_committed(
        committed_by_arrival(Mailbox),
        Clauses,
        Mailbox#mailbox.id,
        Mailbox#mailbox.generation
    );
select(_Clauses, #mailbox{}) ->
    error(badarg).

-doc "Consumes a selected message and releases its occupied slot.".
-spec consume(selection(), mailbox()) ->
    {ok, term(), mailbox()} | {error, operation_error(), mailbox()}.
consume(Selection = #selection{}, Mailbox = #mailbox{}) ->
    case selection_generation(Selection, Mailbox) of
        ok -> consume_current(Mailbox, Selection);
        Error -> {error, Error, Mailbox}
    end;
consume(_Selection, Mailbox = #mailbox{}) ->
    {error, stale_selection, Mailbox}.

-doc "Returns capacity, generation, and occupancy counters.".
-spec info(mailbox()) -> map().
info(Mailbox = #mailbox{}) ->
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

%% Performs the serialized admission step and returns an opaque capability for
%% the chosen slot.  The mailbox-full clause comes first to keep that failure
%% path local.
reserve_current(
    Mailbox = #mailbox{capacity = Capacity, slots = Slots},
    _ReservationOwner
)
        when map_size(Slots) >= Capacity ->
    {error, full, Mailbox};
reserve_current(Mailbox = #mailbox{
    id = MailboxId,
    capacity = Capacity,
    generation = Generation,
    next_ticket = Ticket,
    slots = Slots
}, ReservationOwner) ->
    SlotNumber = first_free_slot(0, Capacity, Slots),
    Slot = #slot{
        status = reserved,
        reservation_owner = ReservationOwner,
        generation = Generation,
        ticket = Ticket
    },
    NewMailbox = Mailbox#mailbox{
        next_ticket = Ticket + 1,
        slots = Slots#{SlotNumber => Slot}
    },
    Reservation = #reservation{
        mailbox_id = MailboxId,
        reservation_owner = ReservationOwner,
        generation = Generation,
        slot = SlotNumber,
        ticket = Ticket
    },
    {ok, Reservation, NewMailbox}.

%% Rejects reservation capabilities created for a different mailbox or an
%% earlier logical actor incarnation.
reservation_generation(
    #reservation{mailbox_id = ReservationMailboxId},
    #mailbox{id = MailboxId}
) when ReservationMailboxId =/= MailboxId ->
    invalid_reservation;
reservation_generation(
    #reservation{mailbox_id = MailboxId, generation = Generation},
    #mailbox{id = MailboxId, generation = Generation}
) ->
    ok;
reservation_generation(
    #reservation{mailbox_id = MailboxId, generation = Received},
    #mailbox{id = MailboxId, generation = Expected}
) ->
    {stale_generation, Expected, Received}.

%% Applies the same identity/incarnation check to a selection capability.
selection_generation(
    #selection{mailbox_id = SelectionMailboxId},
    #mailbox{id = MailboxId}
) when SelectionMailboxId =/= MailboxId ->
    stale_selection;
selection_generation(
    #selection{mailbox_id = MailboxId, generation = Generation},
    #mailbox{id = MailboxId, generation = Generation}
) ->
    ok;
selection_generation(
    #selection{mailbox_id = MailboxId, generation = Received},
    #mailbox{id = MailboxId, generation = Expected}
) ->
    {stale_generation, Expected, Received}.

%% Releases a reservation only while its exact slot incarnation is incomplete.
cancel_current(
    Mailbox = #mailbox{slots = Slots},
    #reservation{
        reservation_owner = ReservationOwner,
        slot = SlotNumber,
        ticket = Ticket
    }
) ->
    case Slots of
        #{SlotNumber := #slot{
            status = reserved,
            reservation_owner = ReservationOwner,
            ticket = Ticket
        }} ->
            NewMailbox = Mailbox#mailbox{
                slots = maps:remove(SlotNumber, Slots)
            },
            {ok, NewMailbox};
        _ ->
            {error, invalid_reservation, Mailbox}
    end.

%% Publishes one complete slot and assigns the next global arrival age.  The
%% committed retry is checked first because it is the shorter special case.
commit_current(
    Mailbox = #mailbox{next_arrival = Arrival, slots = Slots},
    #reservation{
        reservation_owner = ReservationOwner,
        slot = SlotNumber,
        ticket = Ticket
    },
    Message
) ->
    case Slots of
        #{SlotNumber := #slot{status = committed, ticket = Ticket}} ->
            {error, already_committed, Mailbox};
        #{SlotNumber := #slot{
            status = reserved,
            reservation_owner = ReservationOwner,
            ticket = Ticket
        } = Slot} ->
            CommittedSlot = Slot#slot{
                status = committed,
                arrival = Arrival,
                message = Message
            },
            NewMailbox = Mailbox#mailbox{
                next_arrival = Arrival + 1,
                slots = Slots#{SlotNumber => CommittedSlot}
            },
            {ok, NewMailbox};
        _ ->
            {error, invalid_reservation, Mailbox}
    end.

%% Materializes committed slots in their transport-assigned arrival order.
committed_by_arrival(#mailbox{slots = Slots}) ->
    lists:keysort(1, [
        {Arrival, SlotNumber, Slot}
        || {SlotNumber, Slot = #slot{
                status = committed,
                arrival = Arrival
            }} <- maps:to_list(Slots)
    ]).

%% Scans messages before clauses, which is the ordering required by Erlang's
%% selective receive rather than a clause-major search.
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

%% Returns the first source-order predicate accepting one message.
first_matching_clause(_Message, [], _Index) ->
    none;
first_matching_clause(Message, [Clause | Rest], Index) ->
    case Clause(Message) of
        true -> Index;
        false -> first_matching_clause(Message, Rest, Index + 1);
        Result -> error({invalid_mailbox_clause_result, Index, Result})
    end.

%% Consumes only the exact committed slot observed by select/2, protecting a
%% subsequently reused physical slot from an old selection capability.
consume_current(
    Mailbox = #mailbox{slots = Slots},
    #selection{
        slot = SlotNumber,
        ticket = Ticket,
        arrival = Arrival
    }
) ->
    case Slots of
        #{SlotNumber := #slot{
            status = committed,
            ticket = Ticket,
            arrival = Arrival,
            message = Message
        }} ->
            NewMailbox = Mailbox#mailbox{
                slots = maps:remove(SlotNumber, Slots)
            },
            {ok, Message, NewMailbox};
        _ ->
            {error, stale_selection, Mailbox}
    end.

%% Finds the first unoccupied physical slot.  reserve_current/2 has already
%% established that one exists.
first_free_slot(Index, Capacity, Slots) when Index < Capacity ->
    case Slots of
        #{Index := _} -> first_free_slot(Index + 1, Capacity, Slots);
        _ -> Index
    end.

%% Checks the public predicate-list contract once before a mailbox scan.
validate_clauses(Clauses) ->
    case lists:all(fun(Clause) -> is_function(Clause, 1) end, Clauses) of
        true -> ok;
        false -> error(badarg)
    end.
