-module(hls_domain_channel_tx).
-moduledoc """
Source ownership for one directed mailbox crossing on an independently clocked role.

A host-confirmed receiver binding admits one source publication at a time. The
wrapper holds its payload/slot until an exact acknowledgement returns after immutable whole-packet
handoff to retained carrier storage. No retry, remote-liveness inference or same-edge forwarding
is provided. A peer may fail after confirmation; local admission stops when that
uncertainty is explicitly fenced, or immediately when this local domain changes.

Retain this kernel outside the local domain reset region. Warm rebind requires
both endpoint incarnations to advance in the same link namespace. Cold reset
requires external exclusion of the forgotten namespace. The outer carrier checks
the static channel identity, packet integrity and canonical payload. A matching
ACK is trusted to come from the companion RX kernel after native capture.

State is 291 bits plus one external payload/slot. Four TX and four RX endpoints,
two 32-word packet buffers and 512 framing/arbitration bits have a 10,752-bit
per-role ceiling for this link layer, excluding the existing board shell. Each
endpoint has one writer; the carrier selects one complete packet at a time.
""".
-behaviour(hls_gs).
-hls_data(endpoint_tx_service).
-hls_tags([endpoint_tx_input, endpoint_tx_output, endpoint_tx_unsupported]).
-hls_replies([{endpoint_tx_input, [endpoint_tx_output]}]).
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Native and source-compiled ownership transitions.
-export([new/0, step/2]).
-export_type([state/0, input/0, output/0]).
%% Thin source service; the external wrapper owns the sole payload register.
-export([init/1, handle_call/2, handle_cast/2]).

%% The service carries exactly the explicit kernel state, with no hidden queue.
-record(endpoint_tx_service, {channel = #endpoint_tx_state{} :: #endpoint_tx_state{}}).
%% Application casts do not participate in channel ownership.
-record(endpoint_tx_unsupported, {unused = 0 :: hls_nums:u32()}).

-doc "Retained source binding, sequence and one publication's metadata; no payload history.".
-type state() :: #endpoint_tx_state{}.
-doc "Local lifecycle, explicit binding evidence and independent source/transmit/ACK handshakes.".
-type input() :: #endpoint_tx_input{}.
-doc "Next metadata state and old-state handshakes for the external payload wrapper.".
-type output() :: #endpoint_tx_output{}.

-doc "Starts closed and unbound; no source publication is admitted automatically.".
-spec new() -> #endpoint_tx_state{}.
new() -> #endpoint_tx_state{}.

-doc "Applies one local edge. Bind/fence edges transfer no application data; local lifecycle mismatch closes even when control is stale. Carrier acceptance retains a whole TX packet; a peer ACK is valid only after the destination captured that publication. Neither a timeout nor an unmatched ACK releases source ownership.".
-spec step(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
step(Input, State) ->
    case Input#endpoint_tx_input.op of
        tick -> tick(Input, State);
        bind -> bind(Input, observed(Input, State));
        fence -> fence(Input, observed(Input, State))
    end.

%% A stale management request cannot conceal a local incarnation change.
-spec observed(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_state{}.
observed(Input, State) ->
    case State#endpoint_tx_state.active andalso not local_match(Input, State) of
        true -> close(State);
        false -> State
    end.

%% There is deliberately no observation of the remote domain on this edge.
-spec local_match(#endpoint_tx_input{}, #endpoint_tx_state{}) -> boolean().
local_match(Input, State) ->
    Input#endpoint_tx_input.local_ready andalso
        Input#endpoint_tx_input.local_incarnation =:=
            (State#endpoint_tx_state.binding)#endpoint_binding.source_incarnation.

%% Receiver evidence is exact management confirmation, not a synchronous peer-ready wire.
-spec bind(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
bind(Input, State) ->
    Binding = Input#endpoint_tx_input.binding,
    Ready =
        Input#endpoint_tx_input.local_ready andalso
            Input#endpoint_tx_input.local_incarnation =:=
                Binding#endpoint_binding.source_incarnation,
    Confirmed =
        Input#endpoint_tx_input.receiver_active andalso
            Input#endpoint_tx_input.receiver_binding =:= Binding,
    case Ready andalso Confirmed of
        false ->
            result(busy, State);
        true ->
            case binding_status(Binding, State#endpoint_tx_state.binding) of
                accepted -> result(accepted, #endpoint_tx_state{binding = Binding, active = true});
                exhausted -> result(exhausted, close(State));
                Status -> result(Status, State)
            end
    end.

%% Keep record ownership local; the imported identity rule takes only scalars.
-spec binding_status(#endpoint_binding{}, #endpoint_binding{}) -> endpoint_status().
binding_status(Binding, Previous) ->
    hls_domain_channel_binding:advance(
        Binding#endpoint_binding.namespace,
        Binding#endpoint_binding.generation,
        Binding#endpoint_binding.source_incarnation,
        Binding#endpoint_binding.destination_incarnation,
        Previous#endpoint_binding.namespace,
        Previous#endpoint_binding.generation,
        Previous#endpoint_binding.source_incarnation,
        Previous#endpoint_binding.destination_incarnation
    ).

%% Fence names the complete binding so old control cannot close a replacement.
-spec fence(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
fence(Input, State) ->
    case Input#endpoint_tx_input.binding =:= State#endpoint_tx_state.binding of
        true -> result(accepted, close(State));
        false -> result(stale, State)
    end.

%% The local closing edge has no handshake; later closed edges drain old credits.
-spec tick(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
tick(Input, State) ->
    case State#endpoint_tx_state.active of
        false ->
            (result(closed, State))#endpoint_tx_output{
                credit_ready = true, credit_drop = Input#endpoint_tx_input.credit_valid
            };
        true ->
            case local_match(Input, State) of
                false -> result(closed, close(State));
                true -> checked_transfer(Input, State)
            end
    end.

%% Current-binding future or premature ACKs indicate a broken carrier contract.
-spec checked_transfer(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
checked_transfer(Input, State) ->
    Credit = Input#endpoint_tx_input.credit_packet,
    Sequence = Credit#endpoint_packet.sequence,
    Invalid =
        Input#endpoint_tx_input.credit_valid andalso
            Credit#endpoint_packet.binding =:= State#endpoint_tx_state.binding andalso
            (Sequence =:= 0 orelse Sequence > State#endpoint_tx_state.sequence orelse
                (Sequence =:= State#endpoint_tx_state.sequence andalso
                    State#endpoint_tx_state.tx_pending)),
    case Invalid of
        true -> result(invalid, close(State));
        false -> transfer(Input, State)
    end.

%% The last sequence may finish; only a later attempted capture exhausts the binding.
-spec transfer(#endpoint_tx_input{}, #endpoint_tx_state{}) -> #endpoint_tx_output{}.
transfer(Input, State) ->
    Capture = Input#endpoint_tx_input.source_valid andalso not State#endpoint_tx_state.inflight,
    case Capture andalso State#endpoint_tx_state.sequence =:= ((1 bsl 32) - 1) of
        true -> result(exhausted, close(State));
        false -> transfer_ready(Input, State, Capture)
    end.

%% An ACK on the final transmission edge is still premature, and cannot enable capture.
-spec transfer_ready(#endpoint_tx_input{}, #endpoint_tx_state{}, boolean()) ->
    #endpoint_tx_output{}.
transfer_ready(Input, State, Capture) ->
    CreditCurrent =
        State#endpoint_tx_state.inflight andalso not State#endpoint_tx_state.tx_pending andalso
            Input#endpoint_tx_input.credit_packet =:= packet(State),
    CreditTake = Input#endpoint_tx_input.credit_valid andalso CreditCurrent,
    Next =
        case Capture of
            true ->
                State#endpoint_tx_state{
                    sequence = State#endpoint_tx_state.sequence + 1,
                    inflight = true,
                    tx_pending = true
                };
            false ->
                case CreditTake of
                    true ->
                        State#endpoint_tx_state{inflight = false, tx_pending = false};
                    false ->
                        State#endpoint_tx_state{
                            tx_pending =
                                State#endpoint_tx_state.tx_pending andalso
                                    not Input#endpoint_tx_input.data_tx_ready
                        }
                end
        end,
    #endpoint_tx_output{
        state = Next,
        source_take = Capture,
        tx_valid = State#endpoint_tx_state.tx_pending,
        credit_ready = true,
        credit_drop = Input#endpoint_tx_input.credit_valid andalso not CreditCurrent,
        packet = packet(Next)
    }.

%% Payload ownership is abandoned on closure, while all identity tombstones remain.
-spec close(#endpoint_tx_state{}) -> #endpoint_tx_state{}.
close(State) -> State#endpoint_tx_state{active = false, inflight = false, tx_pending = false}.

%% Packet metadata derives from the single authoritative binding and sequence.
-spec packet(#endpoint_tx_state{}) -> #endpoint_packet{}.
packet(State) ->
    #endpoint_packet{
        binding = State#endpoint_tx_state.binding, sequence = State#endpoint_tx_state.sequence
    }.

%% Control and fault edges advertise no packet handshakes.
-spec result(endpoint_status(), #endpoint_tx_state{}) -> #endpoint_tx_output{}.
result(Status, State) ->
    #endpoint_tx_output{status = Status, state = State, packet = packet(State)}.

-doc "Initializes the optional source service with the same closed native kernel state.".
-spec init([]) -> #endpoint_tx_service{}.
init([]) -> #endpoint_tx_service{}.

-doc "Runs one ownership edge and retains only its next metadata state.".
-spec handle_call(#endpoint_tx_input{}, #endpoint_tx_service{}) ->
    {reply, #endpoint_tx_output{}, #endpoint_tx_service{}}.
handle_call(Input = #endpoint_tx_input{}, Service) ->
    Output = step(Input, Service#endpoint_tx_service.channel),
    {reply, Output, Service#endpoint_tx_service{channel = Output#endpoint_tx_output.state}}.

-doc "Rejects application casts as an ownership path by leaving the service unchanged.".
-spec handle_cast(#endpoint_tx_unsupported{}, #endpoint_tx_service{}) ->
    {noreply, #endpoint_tx_service{}}.
handle_cast(#endpoint_tx_unsupported{}, Service) -> {noreply, Service}.
