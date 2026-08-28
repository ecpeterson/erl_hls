-module(xls_tx_table).
-moduledoc """
A fixed-capacity semantic model for split-phase actor requests.

This is a state value owned by a trusted adapter or translated-process runtime,
not a server and not a table exposed to remote peers.  It correlates replies
for operations such as adapter calls or suspended actor requests.  The
`request_owner` retained in each entry identifies the local caller or
continuation to resume.

Opening a transaction reserves a correlation slot before its request is sent.
`mark_sent/2` is the local half of the transport's atomic admission commit.  A
scheduler must publish the sent state no later than it makes the request visible
to its destination; it is not a notification performed after the callee can
reply.  Replies are then matched by peer incarnation, transaction
reference, protocol epoch, and reply tag, so they may complete out of issue
order without entering the actor's ordinary application mailbox.

Completion and retirement are separate.  A reply, cancellation, or timeout
stores one terminal value in the occupied slot.  The owner may resume later and
calls `retire/2` only after consuming that value.  This preserves bounded
completion storage even while the owner is not scheduled.

References contain two distinct reuse barriers.  The table `incarnation`
identifies one lifetime of the adapter or runtime table.  Each slot's
`generation` increments whenever that finite correlation slot is reused.
Together they prevent a delayed reply from an earlier table lifetime or slot
use from completing a new request with the same slot number.  `new/1` supplies
an identity unique only within the current BEAM instance; a restart-safe
adapter must negotiate or persist a fresh value and pass it to `new/2`.

The CPU model treats its counters as unbounded.  A finite fabric encoding will
need explicit rollover and quiescence rules.
""".

-export([
    new/1,
    new/2,
    open/2,
    mark_sent/2,
    complete/6,
    cancel/3,
    expire/3,
    cancel_peer/3,
    cancel_owner/3,
    retire/2,
    lookup/2,
    info/1
]).

-export_type([
    table/0,
    transaction/0,
    transaction_spec/0,
    tx_ref/0,
    peer_ref/0,
    deadline/0
]).

-type tx_ref() :: {
    TableIncarnation :: non_neg_integer(),
    Slot :: 0..255,
    SlotGeneration :: pos_integer()
}.
-type peer_ref() :: {
    Endpoint :: term(),
    PeerIncarnation :: non_neg_integer()
}.
-type deadline() ::
    infinity |
    {ClockDomain :: term(), At :: integer()}.
-type transaction_state() :: reserved | sent | completed.
-type completion() ::
    {reply, Tag :: term(), Value :: term()} |
    {canceled, Reason :: term()} |
    {timeout, admission | reply, ClockDomain :: term()}.
-type transaction_spec() :: #{
    peer := peer_ref(),
    request_owner := term(),
    request_tag := term(),
    protocol_epoch := term(),
    expected_replies := any | [term()],
    deadline := deadline(),
    meta => term()
}.
-type transaction() :: #{
    ref := tx_ref(),
    peer := peer_ref(),
    request_owner := term(),
    request_tag := term(),
    protocol_epoch := term(),
    expected_replies := any | [term()],
    deadline := deadline(),
    meta := term(),
    state := transaction_state(),
    opened := non_neg_integer(),
    completion => completion()
}.

-record(table, {
    capacity :: 1..256,
    incarnation :: non_neg_integer(),
    free :: queue:queue(0..255),
    generations :: tuple(),
    occupied = #{} :: #{0..255 => transaction()},
    next_opened = 0 :: non_neg_integer()
}).

-opaque table() :: #table{}.

-doc """
Creates a table with an incarnation unique within the current BEAM instance.
Use `new/2` whenever replies may outlive reconstruction of that instance.
""".
-spec new(1..256) -> table().
new(Capacity) ->
    new(Capacity, erlang:unique_integer([monotonic, positive])).

-doc """
Creates a table with an adapter- or supervisor-supplied incarnation.  The
caller must not reuse that value while a reply from its earlier use can survive.
""".
-spec new(1..256, non_neg_integer()) -> table().
new(Capacity, Incarnation)
        when is_integer(Capacity), Capacity >= 1, Capacity =< 256,
             is_integer(Incarnation), Incarnation >= 0 ->
    #table{
        capacity = Capacity,
        incarnation = Incarnation,
        free = queue:from_list(lists:seq(0, Capacity - 1)),
        generations = erlang:make_tuple(Capacity, 0)
    };
new(_Capacity, _Incarnation) ->
    error(badarg).

-doc """
Reserves a correlation slot before sending a request.  `Spec` must identify
the remote endpoint and its incarnation, the local `request_owner`, the protocol
epoch, accepted reply tags, and a named-domain deadline or `infinity`.
""".
-spec open(transaction_spec(), table()) ->
    {ok, tx_ref(), table()} |
    {error, full}.
open(
    #{
        peer := {_PeerEndpoint, PeerGeneration},
        request_owner := _RequestOwner,
        request_tag := _RequestTag,
        protocol_epoch := _ProtocolEpoch,
        expected_replies := ExpectedReplies,
        deadline := Deadline
    } = Spec,
    Table = #table{free = Free0}
)
        when is_integer(PeerGeneration), PeerGeneration >= 0,
             (ExpectedReplies =:= any orelse is_list(ExpectedReplies)) ->
    case valid_deadline(Deadline) of
        false ->
            error(badarg);
        true ->
            case queue:out(Free0) of
                {empty, _Free} ->
                    {error, full};
                {{value, Slot}, Free1} ->
                    open_slot(Slot, Free1, Spec, Table)
            end
    end;
open(_Spec, _Table) ->
    error(badarg).

-doc """
Marks a reserved transaction sent as part of the transport's admission commit.
The scheduler must install this state before or atomically with destination
visibility.  Acceptance of an individual framing beat is not sufficient.
""".
-spec mark_sent(tx_ref(), table()) ->
    {ok, table()} |
    {error,
        unknown_transaction |
        stale_transaction |
        already_completed |
        {invalid_state, sent}}.
mark_sent(Ref = {_Incarnation, Slot, _Generation}, Table) ->
    case resolve(Ref, Table) of
        {error, Reason} ->
            {error, Reason};
        {ok, #{state := sent}} ->
            {error, {invalid_state, sent}};
        {ok, #{state := completed}} ->
            {error, already_completed};
        {ok, #{state := reserved} = Transaction} ->
            {ok, replace_transaction(
                Slot,
                Transaction#{state => sent},
                Table
            )}
    end;
mark_sent(_Ref, _Table) ->
    {error, unknown_transaction}.

-doc """
Stores a reply in a sent transaction after validating the replying endpoint
incarnation, protocol epoch, reference, and reply tag.  The occupied slot is
retained until `retire/2` consumes the terminal value.
""".
-spec complete(peer_ref(), tx_ref(), term(), term(), term(), table()) ->
    {ok, transaction(), table()} |
    {error,
        unknown_transaction |
        stale_transaction |
        not_sent |
        already_completed |
        {peer_mismatch, peer_ref()} |
        {epoch_mismatch, term()} |
        {unexpected_reply, [term()]}}.
complete(Peer, Ref = {_Incarnation, Slot, _Generation}, ProtocolEpoch,
        ReplyTag, Reply, Table) ->
    case resolve(Ref, Table) of
        {error, Reason} ->
            {error, Reason};
        {ok, #{state := reserved}} ->
            {error, not_sent};
        {ok, #{state := completed}} ->
            {error, already_completed};
        {ok, #{state := sent} = Transaction} ->
            complete_sent(
                Peer,
                ProtocolEpoch,
                ReplyTag,
                Reply,
                Slot,
                Transaction,
                Table
            )
    end;
complete(_Peer, _Ref, _ProtocolEpoch, _ReplyTag, _Reply, _Table) ->
    {error, unknown_transaction}.

-doc """
Stores a cancellation as the transaction's terminal value.  Cancellation never
overwrites an existing terminal outcome.
""".
-spec cancel(tx_ref(), term(), table()) ->
    {ok, transaction(), table()} |
    {error, unknown_transaction | stale_transaction | already_completed}.
cancel(Ref = {_Incarnation, Slot, _Generation}, Reason, Table) ->
    case resolve(Ref, Table) of
        {error, Error} ->
            {error, Error};
        {ok, #{state := completed}} ->
            {error, already_completed};
        {ok, Transaction} ->
            {Completed, NewTable} = store_completion(
                Slot,
                {canceled, Reason},
                Transaction,
                Table
            ),
            {ok, Completed, NewTable}
    end;
cancel(_Ref, _Reason, _Table) ->
    {error, unknown_transaction}.

-doc """
Completes every unfinished deadline in `ClockDomain` at or before `Now`.
Reserved requests receive an admission timeout and sent requests receive a
reply timeout.  Results are ordered by deadline and then opening order.
""".
-spec expire(term(), integer(), table()) -> {[transaction()], table()}.
expire(ClockDomain, Now, Table = #table{occupied = Occupied})
        when is_integer(Now) ->
    Candidates = lists:sort([
        {Deadline, Opened, Slot, Transaction}
        || {Slot, #{
                state := State,
                deadline := {TransactionDomain, Deadline},
                opened := Opened
            } = Transaction} <- maps:to_list(Occupied),
           (State =:= reserved orelse State =:= sent),
           TransactionDomain =:= ClockDomain,
           Deadline =< Now
    ]),
    expire_transactions(ClockDomain, Candidates, Table);
expire(_ClockDomain, _Now, _Table) ->
    error(badarg).

-doc """
Cancels every unfinished transaction for one exact peer incarnation.  Terminal
values remain occupied until their respective owners retire them.
""".
-spec cancel_peer(peer_ref(), term(), table()) -> {[transaction()], table()}.
cancel_peer(Peer, Reason, Table = #table{occupied = Occupied}) ->
    Candidates = lists:sort([
        {Opened, Slot, Transaction}
        || {Slot, #{
                state := State,
                peer := TransactionPeer,
                opened := Opened
            } = Transaction} <- maps:to_list(Occupied),
           State =/= completed,
           TransactionPeer =:= Peer
    ]),
    cancel_transactions(Candidates, Reason, Table).

-doc """
Returns every transaction belonging to `RequestOwner`.  Unfinished entries are
canceled; existing terminal outcomes are preserved.  A runtime uses this when a
caller or continuation dies, then retires every returned entry after performing
any remaining diagnostics or failure propagation.
""".
-spec cancel_owner(term(), term(), table()) -> {[transaction()], table()}.
cancel_owner(RequestOwner, Reason, Table = #table{occupied = Occupied}) ->
    Candidates = lists:sort([
        {Opened, Slot, Transaction}
        || {Slot, #{
                request_owner := TransactionOwner,
                opened := Opened
            } = Transaction} <- maps:to_list(Occupied),
           TransactionOwner =:= RequestOwner
    ]),
    cleanup_owner_transactions(Candidates, Reason, Table).

-doc """
Consumes one terminal transaction and releases its correlation slot.  A live
reserved or sent transaction cannot be retired.
""".
-spec retire(tx_ref(), table()) ->
    {ok, transaction(), table()} |
    {error, unknown_transaction | stale_transaction | not_completed}.
retire(Ref = {_Incarnation, Slot, _Generation}, Table) ->
    case resolve(Ref, Table) of
        {error, Reason} ->
            {error, Reason};
        {ok, #{state := completed} = Transaction} ->
            {ok, Transaction, release_slot(Slot, Table)};
        {ok, _Transaction} ->
            {error, not_completed}
    end;
retire(_Ref, _Table) ->
    {error, unknown_transaction}.

-doc "Looks up one occupied transaction, including an unretired completion.".
-spec lookup(tx_ref(), table()) -> {ok, transaction()} | error.
lookup(Ref, Table) ->
    case resolve(Ref, Table) of
        {error, _Reason} -> error;
        {ok, Transaction} -> {ok, Transaction}
    end.

-doc "Returns capacity and occupancy counts by transaction state.".
-spec info(table()) -> #{
    capacity := pos_integer(),
    free := non_neg_integer(),
    occupied := non_neg_integer(),
    reserved := non_neg_integer(),
    sent := non_neg_integer(),
    completed := non_neg_integer()
}.
info(#table{capacity = Capacity, free = Free, occupied = Occupied}) ->
    Transactions = maps:values(Occupied),
    Reserved = count_state(reserved, Transactions),
    Sent = count_state(sent, Transactions),
    Completed = count_state(completed, Transactions),
    #{
        capacity => Capacity,
        free => queue:len(Free),
        occupied => map_size(Occupied),
        reserved => Reserved,
        sent => Sent,
        completed => Completed
    }.

%% Constructs a transaction after open/2 has serialized admission and selected
%% a free slot.
open_slot(Slot, Free1, #{
    peer := Peer,
    request_owner := RequestOwner,
    request_tag := RequestTag,
    protocol_epoch := ProtocolEpoch,
    expected_replies := ExpectedReplies,
    deadline := Deadline
} = Spec, Table) ->
    Generations0 = Table#table.generations,
    Generation = element(Slot + 1, Generations0) + 1,
    Generations1 = setelement(Slot + 1, Generations0, Generation),
    Ref = {Table#table.incarnation, Slot, Generation},
    Opened = Table#table.next_opened,
    Transaction = #{
        ref => Ref,
        peer => Peer,
        request_owner => RequestOwner,
        request_tag => RequestTag,
        protocol_epoch => ProtocolEpoch,
        expected_replies => ExpectedReplies,
        deadline => Deadline,
        meta => maps:get(meta, Spec, undefined),
        state => reserved,
        opened => Opened
    },
    Occupied1 = (Table#table.occupied)#{Slot => Transaction},
    {ok, Ref, Table#table{
        free = Free1,
        generations = Generations1,
        occupied = Occupied1,
        next_opened = Opened + 1
    }}.

%% Validates independent envelope fields before storing the terminal reply.
complete_sent(Peer, ProtocolEpoch, ReplyTag, Reply, Slot,
        Transaction, Table) ->
    case validate_reply(Peer, ProtocolEpoch, ReplyTag, Transaction) of
        {error, _Reason} = Error ->
            Error;
        ok ->
            {Completed, NewTable} = store_completion(
                Slot,
                {reply, ReplyTag, Reply},
                Transaction,
                Table
            ),
            {ok, Completed, NewTable}
    end.

%% Structural peer equality includes the remote endpoint generation.
validate_reply(Peer, _ProtocolEpoch, _ReplyTag,
        #{peer := ExpectedPeer}) when Peer =/= ExpectedPeer ->
    {error, {peer_mismatch, ExpectedPeer}};
validate_reply(_Peer, ProtocolEpoch, _ReplyTag,
        #{protocol_epoch := ExpectedEpoch})
        when ProtocolEpoch =/= ExpectedEpoch ->
    {error, {epoch_mismatch, ExpectedEpoch}};
validate_reply(_Peer, _ProtocolEpoch, _ReplyTag,
        #{expected_replies := any}) ->
    ok;
validate_reply(_Peer, _ProtocolEpoch, ReplyTag,
        #{expected_replies := ExpectedReplies}) ->
    case lists:member(ReplyTag, ExpectedReplies) of
        false -> {error, {unexpected_reply, ExpectedReplies}};
        true -> ok
    end.

%% Stores exactly one terminal outcome in an occupied slot.
store_completion(Slot, Completion, Transaction, Table) ->
    Completed = Transaction#{
        state => completed,
        completion => Completion
    },
    {Completed, replace_transaction(Slot, Completed, Table)}.

%% Completes deadline candidates without revisiting entries already terminal.
expire_transactions(ClockDomain, Candidates, Table0) ->
    lists:mapfoldl(
        fun({_Deadline, _Opened, Slot,
                #{state := State} = Transaction}, Table) ->
            Completion = {timeout, timeout_phase(State), ClockDomain},
            {Completed, NewTable} = store_completion(
                Slot,
                Completion,
                Transaction,
                Table
            ),
            {Completed, NewTable}
        end,
        Table0,
        Candidates
    ).

%% Distinguishes a request which never left from one awaiting a reply.
timeout_phase(reserved) -> admission;
timeout_phase(sent) -> reply.

%% Applies one cancellation reason to a stable, opening-ordered candidate list.
cancel_transactions(Candidates, Reason, Table0) ->
    lists:mapfoldl(
        fun({_Opened, Slot, Transaction}, Table) ->
            {Completed, NewTable} = store_completion(
                Slot,
                {canceled, Reason},
                Transaction,
                Table
            ),
            {Completed, NewTable}
        end,
        Table0,
        Candidates
    ).

%% Makes owner death a complete bounded cleanup operation.  Terminal entries
%% remain unchanged so a reply cannot be rewritten as a cancellation.
cleanup_owner_transactions(Candidates, Reason, Table0) ->
    lists:mapfoldl(
        fun
            ({_Opened, _Slot, #{state := completed} = Transaction}, Table) ->
                {Transaction, Table};
            ({_Opened, Slot, Transaction}, Table) ->
                store_completion(
                    Slot,
                    {canceled, Reason},
                    Transaction,
                    Table
                )
        end,
        Table0,
        Candidates
    ).

%% Resolves a reference by table incarnation, bounded slot, and slot
%% generation.  A numerically future generation is unknown rather than stale.
resolve(
    {ReceivedIncarnation, _Slot, _Generation},
    #table{incarnation = Incarnation}
) when ReceivedIncarnation =/= Incarnation ->
    {error, stale_transaction};
resolve(Ref = {Incarnation, Slot, Generation}, #table{
    capacity = Capacity,
    incarnation = Incarnation,
    generations = Generations,
    occupied = Occupied
})
        when is_integer(Slot), Slot >= 0, Slot < Capacity,
             is_integer(Generation), Generation > 0 ->
    case Occupied of
        #{Slot := #{ref := Ref} = Transaction} ->
            {ok, Transaction};
        #{Slot := #{ref := {_Incarnation, Slot, CurrentGeneration}}} ->
            generation_error(Generation, CurrentGeneration);
        _ ->
            CurrentGeneration = element(Slot + 1, Generations),
            generation_error(Generation, CurrentGeneration)
    end;
resolve(_Ref, _Table) ->
    {error, unknown_transaction}.

%% Classifies only an older slot use as stale; an unallocated or forged future
%% use remains unknown.
generation_error(Received, Current) when Received < Current ->
    {error, stale_transaction};
generation_error(_Received, _Current) ->
    {error, unknown_transaction}.

%% Replaces one occupied slot without changing capacity accounting.
replace_transaction(Slot, Transaction,
        Table = #table{occupied = Occupied}) ->
    Table#table{occupied = Occupied#{Slot := Transaction}}.

%% Releases capacity only after the terminal value has been consumed.
release_slot(Slot, Table = #table{free = Free0, occupied = Occupied0}) ->
    Table#table{
        free = queue:in(Slot, Free0),
        occupied = maps:remove(Slot, Occupied0)
    }.

%% Counts one transaction state for diagnostic capacity reporting.
count_state(State, Transactions) ->
    length([ok || #{state := TransactionState} <- Transactions,
                  TransactionState =:= State]).

%% Checks the named-domain deadline representation at the public boundary.
valid_deadline(infinity) ->
    true;
valid_deadline({_ClockDomain, At}) ->
    is_integer(At);
valid_deadline(_Deadline) ->
    false.
