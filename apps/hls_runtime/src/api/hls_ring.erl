-module(hls_ring).
-moduledoc """
Bounded circular storage with a resumable cursor, shared by BEAM and hardware.

Rewind and advance to inspect entries in queue order. Insertion at the cursor
first reserves a free slot; each insert_step moves one suffix entry, then a
final step installs the supplied value (earlier steps ignore it).
Only the head can be popped. Readers cannot observe an unfinished insertion.

These operations do not schedule work: an actor chooses its continuation
boundaries. No predicate or callback is stored in the ring. Elements retain
their hls_type representation; the four cursor words add 128 state bits.
""".
-behaviour(hls_type).
%% Cursor traversal and element access.
-export([rewind/1, at_end/1, next/1, current/1, replace/2]).
%% Incremental insertion and head retirement.
-export([full/1, begin_insert/1, insert_step/2, empty/1, front/1, pop/1]).
%% Type constructor and shared codec schema.
-export([ring/2, fields/2]).
-export_type([ring/2]).
%% hls_type callbacks.
-export([width/2, value_width/2, zero/2, pack/3, unpack/3]).

%% Positions are one-based; zero insertion means ordinary traversal.
-record(ring, {values, head = 0, size = 0, position = 0, insertion = 0}).
-doc "Opaque fixed-capacity storage and its resumable cursor; construct with hls_type:zero/1.".
-opaque ring(T, N) :: #ring{
    values :: hls_vec:vector(T, N),
    head :: hls_nums:u32(),
    size :: hls_nums:u32(),
    position :: hls_nums:u32(),
    insertion :: hls_nums:u32()
}.

-doc "Describes positive capacity below 2^31, with a concrete element type.".
-spec ring(hls_type:descriptor(), pos_integer()) -> hls_type:descriptor().
ring(T, N) when is_integer(N), N > 0, N < (1 bsl 31) -> {hls_type, ?MODULE, ring, [T, N]};
ring(_, _) -> error(badarg).

-doc "Starts traversal at the head. Rejects an unfinished insertion.".
-spec rewind(ring(T, N)) -> ring(T, N).
rewind(Q = #ring{insertion = 0}) -> Q#ring{position = 1};
rewind(_) -> error(badarg).

-doc "True before traversal starts or after its last entry; rejects an unfinished insertion.".
-spec at_end(ring(_, _)) -> boolean().
at_end(#ring{insertion = 0, position = P, size = S}) -> P =:= 0 orelse P > S;
at_end(_) -> error(badarg).

-doc "Advances one live cursor entry; advancing an exhausted cursor raises badarg.".
-spec next(ring(T, N)) -> ring(T, N).
next(Q = #ring{position = P}) ->
    require(not at_end(Q)),
    Q#ring{position = P + 1}.

-doc "Reads the live cursor entry; an exhausted cursor raises badarg.".
-spec current(ring(T, _)) -> T.
current(Q = #ring{position = P}) ->
    require(not at_end(Q)),
    read(P, Q).

-doc "Replaces the live cursor entry without changing order; exhaustion raises badarg.".
-spec replace(T, ring(T, N)) -> ring(T, N).
replace(V, Q = #ring{position = P}) ->
    require(not at_end(Q)),
    write(P, V, Q).

-doc "True when no insertion slot remains; rejects an unfinished insertion.".
-spec full(ring(_, _)) -> boolean().
full(#ring{insertion = 0, size = S, values = V}) -> S =:= length(V);
full(_) -> error(badarg).

-doc "Reserves insertion before the cursor (or at the exhausted tail). Requires a started cursor and a free slot, otherwise badarg.".
-spec begin_insert(ring(T, N)) -> ring(T, N).
begin_insert(Q = #ring{position = P, size = S}) ->
    require(not full(Q) andalso P >= 1 andalso P =< S + 1),
    Q#ring{insertion = P, position = S}.

-doc "Moves one suffix entry, or installs Value and returns {true, Ring}. Earlier steps ignore Value. Continue with the returned ring while false; requires begin_insert/1.".
-spec insert_step(T, ring(T, N)) -> {boolean(), ring(T, N)}.
insert_step(V, Q = #ring{position = P, insertion = I, size = S}) when I > 0 ->
    case P >= I of
        true -> {false, (write(P + 1, read(P, Q), Q))#ring{position = P - 1}};
        false -> {true, (write(I, V, Q))#ring{size = S + 1, position = I, insertion = 0}}
    end;
insert_step(_, _) ->
    error(badarg).

-doc "True when there is no head; rejects an unfinished insertion.".
-spec empty(ring(_, _)) -> boolean().
empty(#ring{insertion = 0, size = S}) -> S =:= 0;
empty(_) -> error(badarg).

-doc "Reads the head independently of cursor position; an empty ring raises badarg.".
-spec front(ring(T, _)) -> T.
front(Q) ->
    require(not empty(Q)),
    read(1, Q).

-doc "Removes the head and invalidates the old cursor. Empty or unfinished rings raise badarg; rewind before another traversal.".
-spec pop(ring(T, N)) -> ring(T, N).
pop(Q = #ring{head = H, size = S, values = V}) ->
    require(not empty(Q)),
    Q#ring{head = (H + 1) rem length(V), size = S - 1, position = 0}.

%% Slots belong to this module; callers only see queue-order traversal.
-spec slot(pos_integer(), ring(_, _)) -> pos_integer().
slot(P, #ring{head = H, values = V}) -> (H + P - 1) rem length(V) + 1.
%% Read an already validated logical position, including during a shift.
-spec read(pos_integer(), ring(T, _)) -> T.
read(P, Q = #ring{values = V}) -> hls_vec:nth(slot(P, Q), V).
%% Write a live or reserved slot.
-spec write(pos_integer(), T, ring(T, N)) -> ring(T, N).
write(P, V, Q = #ring{values = Values}) -> Q#ring{values = hls_vec:set(slot(P, Q), Values, V)}.
%% Keep native misuse aligned with the hardware provider's failure flag.
-spec require(boolean()) -> ok.
require(true) -> ok;
require(false) -> error(badarg).

-doc "Internal codec schema shared with the compiler; owns field order, not a public record API.".
-spec fields(hls_type:descriptor(), pos_integer()) -> hls_record:fields().
fields(T, N) ->
    _ = ring(T, N),
    [
        {values, hls_vec:vector(T, N)},
        {head, hls_nums:u32()},
        {size, hls_nums:u32()},
        {position, hls_nums:u32()},
        {insertion, hls_nums:u32()}
    ].

-doc "Serialized width, including element padding and four 32-bit cursor words.".
-spec width(ring, [hls_type:arg()]) -> pos_integer().
width(ring, [T, N]) -> hls_record:width(ring, fields(T, N)).
-doc "Logical width, excluding element padding.".
-spec value_width(ring, [hls_type:arg()]) -> pos_integer().
value_width(ring, [T, N]) -> hls_record:value_width(ring, fields(T, N)).
-doc "An empty ring with a not-yet-started cursor and type-directed element zeros.".
-spec zero(ring, [hls_type:arg()]) -> ring(term(), pos_integer()).
zero(ring, [T, N]) -> hls_record:zero(ring, fields(T, N)).
-doc "Packs a valid ring through the shared record/element codecs; rejects malformed cursor state.".
-spec pack(term(), ring, [hls_type:arg()]) -> bitstring().
pack(Q, ring, [T, N]) ->
    validate(Q, N),
    hls_record:pack(Q, ring, fields(T, N)).
-doc "Decodes a ring and trailing bits; rejects impossible cursor state.".
-spec unpack(bitstring(), ring, [hls_type:arg()]) -> {ring(term(), pos_integer()), bitstring()}.
unpack(Bits, ring, [T, N]) ->
    {Q, Rest} = hls_record:unpack(Bits, ring, fields(T, N)),
    validate(Q, N),
    {Q, Rest}.
%% A shifting suffix temporarily has one duplicate; only its metadata is constrained.
-spec validate(term(), pos_integer()) -> ok.
validate(#ring{values = V, head = H, size = S, position = P, insertion = I}, N) when
    is_list(V), length(V) =:= N, H >= 0, H < N, S >= 0, S =< N, P >= 0
->
    require(
        case I of
            0 -> P =< S + 1;
            _ -> S < N andalso I >= 1 andalso I =< S + 1 andalso P >= I - 1 andalso P =< S
        end
    );
validate(_, _) ->
    error(badarg).
