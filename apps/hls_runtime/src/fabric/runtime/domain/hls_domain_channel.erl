-module(hls_domain_channel).
-moduledoc """
Finite ownership of one directed mailbox crossing between reset domains.

The wrapper retains one payload and slot outside both endpoint reset regions. A
source capture owns its sole credit until that exact packet is received, its
acknowledgement is emitted, and the matching credit returns. Decisions use old
state; no capture/transmit, receive/acknowledge or acknowledge/release bypass is
provided. Stale, duplicate and premature transport packets are consumed without
application delivery or credit release.

The caller supplies current endpoint lifecycle observations on every step. Either
endpoint becoming unavailable or changing incarnation closes admission before any
transfer on that edge. Explicit fencing has the same priority. A later tick drains
old transport traffic while closed. Closure discards only local packet metadata;
it does not undo an already accepted destination effect or replay lost work.

Binding is explicit and requires both endpoint incarnations to advance. Replacing
only the destination could reinterpret an untagged old source outbox, so it is
rejected. Generation and packet sequence never wrap. A fresh binding requires the
expected generation; a cold reset which forgets these tombstones requires external
retirement of the former channel namespace. This kernel provides neither process
link signals nor distributed agreement that a remote endpoint has stopped.
""".
-behaviour(hls_gs).
-hls_data(channel_service).
-hls_tags([channel_input, channel_output, unsupported_cast]).
-hls_replies([{channel_input, [channel_output]}]).
-include_lib("hls_runtime/include/hls_domain_channel.hrl").

%% Native and compiled finite ownership policy.
-export([new/0, step/2]).
-export_type([state/0, input/0, output/0, status/0]).
%% Thin source-compiled service adapter; it owns no payload storage.
-export([init/1, handle_call/2, handle_cast/2]).

%% Service state is identical to the state passed explicitly by a native caller.
-record(channel_service, {channel = #channel_state{} :: #channel_state{}}).
%% Application casts cannot bypass the explicit channel input contract.
-record(unsupported_cast, {unused = 0 :: hls_nums:u32()}).

-doc "One binding, nonwrapping sequence and packet ownership outside both endpoint resets.".
-type state() :: #channel_state{}.
-doc "Current endpoint observations and independent ready/valid data and credit handshakes.".
-type input() :: #channel_input{}.
-doc "Updated ownership and this edge's transfer decisions; payload remains in the wrapper.".
-type output() :: #channel_output{}.
-doc "Control disposition; accepted binding does not mean any application packet transferred.".
-type status() :: channel_status().

-doc "Returns an unbound, closed channel with no packet or credit ownership.".
-spec new() -> #channel_state{}.
new() -> #channel_state{}.

-doc "Applies one ordered channel edge. Callers retain state outside endpoint resets, provide current lifecycle observations and obey ready/valid payload stability. Bind and fence transfer no application data. A rejected bind never automatically reconnects; closure cancels in-flight ownership without undoing destination effects.".
-spec step(#channel_input{}, #channel_state{}) -> #channel_output{}.
step(Input, State) ->
    case Input#channel_input.op of
        bind -> bind(Input, observed(Input, State));
        fence -> fence(Input, observed(Input, State));
        tick -> tick(Input, State)
    end.

%% A lifecycle mismatch invalidates old ownership even when the accompanying control is stale.
-spec observed(#channel_input{}, #channel_state{}) -> #channel_state{}.
observed(Input, State) ->
    case State#channel_state.active andalso not endpoints_match(Input, State) of
        true -> close(State);
        false -> State
    end.

%% The two exact nonzero incarnations jointly authorize data transfers for this binding.
-spec endpoints_match(#channel_input{}, #channel_state{}) -> boolean().
endpoints_match(Input, State) ->
    Input#channel_input.source_ready andalso Input#channel_input.destination_live andalso
        Input#channel_input.source_incarnation =:= State#channel_state.source_incarnation andalso
        Input#channel_input.destination_incarnation =:= State#channel_state.destination_incarnation.

%% Binding allocates a generation only after both endpoints advance beyond their tombstones.
-spec bind(#channel_input{}, #channel_state{}) -> #channel_output{}.
bind(Input, State) ->
    case Input#channel_input.expected_generation =:= State#channel_state.generation of
        false ->
            result(stale, State);
        true ->
            Ready = Input#channel_input.source_ready andalso Input#channel_input.destination_live,
            case Ready of
                false -> result(busy, State);
                true -> bind_ready(Input, State)
            end
    end.

%% An unchanged source cannot retag its old unversioned outbox for a replacement destination.
-spec bind_ready(#channel_input{}, #channel_state{}) -> #channel_output{}.
bind_ready(Input, State) ->
    Fresh =
        Input#channel_input.source_incarnation > State#channel_state.source_incarnation andalso
            Input#channel_input.destination_incarnation >
                State#channel_state.destination_incarnation,
    case Fresh of
        false ->
            result(stale, State);
        true ->
            case State#channel_state.generation =:= ((1 bsl 64) - 1) of
                true ->
                    result(exhausted, close(State));
                false ->
                    result(accepted, #channel_state{
                        source_incarnation = Input#channel_input.source_incarnation,
                        destination_incarnation = Input#channel_input.destination_incarnation,
                        generation = State#channel_state.generation + 1,
                        active = true
                    })
            end
    end.

%% Explicit fencing requires the exact channel lifetime and never performs a data handshake.
-spec fence(#channel_input{}, #channel_state{}) -> #channel_output{}.
fence(Input, State) ->
    case Input#channel_input.expected_generation =:= State#channel_state.generation of
        true -> result(accepted, close(State));
        false -> result(stale, State)
    end.

%% The closing edge cannot transfer; later closed ticks drain stale transport packets.
-spec tick(#channel_input{}, #channel_state{}) -> #channel_output{}.
tick(Input, State) ->
    case State#channel_state.active of
        false ->
            discard(Input, State);
        true ->
            case endpoints_match(Input, State) of
                false -> result(closed, close(State));
                true -> transfer(Input, State)
            end
    end.

%% Sequence exhaustion rejects a fresh capture without disturbing a packet still being delivered.
-spec transfer(#channel_input{}, #channel_state{}) -> #channel_output{}.
transfer(Input, State) ->
    Capture = Input#channel_input.source_valid andalso not State#channel_state.inflight,
    case Capture andalso State#channel_state.sequence =:= ((1 bsl 32) - 1) of
        true -> result(exhausted, close(State));
        false -> transfer_ready(Input, State, Capture)
    end.

%% One old-state credit cannot enable source capture on its returning edge.
-spec transfer_ready(#channel_input{}, #channel_state{}, boolean()) -> #channel_output{}.
transfer_ready(Input, State, Capture) ->
    DataCurrent =
        State#channel_state.inflight andalso not State#channel_state.received andalso
            not State#channel_state.tx_pending andalso
            Input#channel_input.data_generation =:= State#channel_state.generation andalso
            Input#channel_input.data_sequence =:= State#channel_state.sequence,
    DestinationValid = Input#channel_input.data_valid andalso DataCurrent,
    DestinationTake = DestinationValid andalso Input#channel_input.destination_ready,
    DataReady = not DataCurrent orelse Input#channel_input.destination_ready,
    CreditCurrent =
        State#channel_state.inflight andalso State#channel_state.received andalso
            not State#channel_state.tx_pending andalso not State#channel_state.ack_pending andalso
            Input#channel_input.credit_generation =:= State#channel_state.generation andalso
            Input#channel_input.credit_sequence =:= State#channel_state.sequence,
    CreditTake = Input#channel_input.credit_valid andalso CreditCurrent,
    Next = packet_state(Input, State, Capture, DestinationTake, CreditTake),
    #channel_output{
        state = Next,
        source_take = Capture,
        tx_valid = State#channel_state.tx_pending,
        data_ready = DataReady,
        data_drop = Input#channel_input.data_valid andalso not DataCurrent,
        destination_valid = DestinationValid,
        destination_take = DestinationTake,
        ack_valid = State#channel_state.ack_pending,
        credit_ready = true,
        credit_drop = Input#channel_input.credit_valid andalso not CreditCurrent,
        generation = Next#channel_state.generation,
        sequence = Next#channel_state.sequence
    }.

%% Packet flags change only for the separately accepted old-state handshakes.
-spec packet_state(#channel_input{}, #channel_state{}, boolean(), boolean(), boolean()) ->
    #channel_state{}.
packet_state(Input, State, Capture, DestinationTake, CreditTake) ->
    case Capture of
        true ->
            State#channel_state{
                sequence = State#channel_state.sequence + 1,
                inflight = true,
                received = false,
                tx_pending = true,
                ack_pending = false
            };
        false ->
            case CreditTake of
                true ->
                    clear_packet(State);
                false ->
                    State#channel_state{
                        tx_pending =
                            State#channel_state.tx_pending andalso
                                not Input#channel_input.data_tx_ready,
                        received = State#channel_state.received orelse DestinationTake,
                        ack_pending =
                            DestinationTake orelse
                                (State#channel_state.ack_pending andalso
                                    not Input#channel_input.ack_tx_ready)
                    }
            end
    end.

%% Closed channels absorb old traffic but cannot create a destination write or return a credit.
-spec discard(#channel_input{}, #channel_state{}) -> #channel_output{}.
discard(Input, State) ->
    (result(closed, State))#channel_output{
        data_ready = true,
        data_drop = Input#channel_input.data_valid,
        credit_ready = true,
        credit_drop = Input#channel_input.credit_valid
    }.

%% Closing preserves all identity tombstones while abandoning the one uncompleted packet.
-spec close(#channel_state{}) -> #channel_state{}.
close(State) -> (clear_packet(State))#channel_state{active = false}.

%% The wrapper may overwrite its payload only after a subsequent accepted source capture.
-spec clear_packet(#channel_state{}) -> #channel_state{}.
clear_packet(State) ->
    State#channel_state{
        inflight = false, received = false, tx_pending = false, ack_pending = false
    }.

%% Control edges and fencing expose no data handshakes.
-spec result(channel_status(), #channel_state{}) -> #channel_output{}.
result(Status, State) ->
    #channel_output{
        status = Status,
        state = State,
        generation = State#channel_state.generation,
        sequence = State#channel_state.sequence
    }.

-doc "Initializes the optional source-compiled service with a closed channel.".
-spec init([]) -> #channel_service{}.
init([]) -> #channel_service{}.

-doc "Applies the same finite ownership step used by native callers and retains its new state.".
-spec handle_call(#channel_input{}, #channel_service{}) ->
    {reply, #channel_output{}, #channel_service{}}.
handle_call(Input = #channel_input{}, Service) ->
    Output = step(Input, Service#channel_service.channel),
    {reply, Output, Service#channel_service{channel = Output#channel_output.state}}.

-doc "Rejects accidental application casts to the management/data ownership kernel.".
-spec handle_cast(#unsupported_cast{}, #channel_service{}) -> {noreply, #channel_service{}}.
handle_cast(#unsupported_cast{unused = Value}, State) ->
    false = Value =:= Value,
    {noreply, State}.
