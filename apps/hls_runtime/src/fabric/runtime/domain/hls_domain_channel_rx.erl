-module(hls_domain_channel_rx).
-moduledoc """
Destination ownership for one directed mailbox crossing on an independent role.

One exact next packet is captured in the wrapper, delivered to native destination
capture on a later edge, then acknowledged on another edge. ACK means native
capture, not actor execution. Stale bindings and duplicate packets are drained
without delivery or another ACK; current-binding reordering or premature traffic closes the endpoint; no application or ACK replay is implemented.
The external payload slot prevents a blocked native capture from occupying the
shared carrier parser. The carrier must separately check channel identity,
framing integrity and canonical source payloads before offering a packet.

Only this local destination's lifecycle is sampled. A failed remote source may
remain unknown until the host fences this binding. Exact binding identities
prevent that old traffic entering a replacement destination. Binding stores a
host-authorized expected peer identity, not distributed agreement or liveness.

Retain metadata outside the local domain reset region. Cold reset requires
external exclusion of the old namespace. State is 291 bits plus one external
payload/slot; together with TX it obeys the declared bounded link-layer budget.
""".
-behaviour(hls_gs).
-hls_data(endpoint_rx_service).
-hls_tags([endpoint_rx_input, endpoint_rx_output, endpoint_rx_unsupported]).
-hls_replies([{endpoint_rx_input, [endpoint_rx_output]}]).
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Native and source-compiled destination ownership transitions.
-export([new/0, step/2]).
-export_type([state/0, input/0, output/0]).
%% Thin source service; the external wrapper retains the sole incoming payload.
-export([init/1, handle_call/2, handle_cast/2]).

%% The service carries exactly the explicit kernel state, without a hidden queue.
-record(endpoint_rx_service, {channel = #endpoint_rx_state{} :: #endpoint_rx_state{}}).
%% Application casts cannot bypass native capture admission.
-record(endpoint_rx_unsupported, {unused = 0 :: hls_nums:u32()}).

-doc "Retained destination binding, sequence and one packet's receive/ACK ownership.".
-type state() :: #endpoint_rx_state{}.
-doc "Local lifecycle, one checked carrier packet and native-capture/ACK readiness.".
-type input() :: #endpoint_rx_input{}.
-doc "Next metadata and old-state handshakes for the incoming payload wrapper.".
-type output() :: #endpoint_rx_output{}.

-doc "Starts closed; peer traffic cannot create or reactivate a binding.".
-spec new() -> #endpoint_rx_state{}.
new() -> #endpoint_rx_state{}.

-doc "Applies one local edge. Only exact next packets with a free slot are captured; old offers are drained without ACK replay, while future or premature current-binding offers close the endpoint. Local lifecycle mismatch closes before every handshake, including stale management control. Each accepted packet, native capture and ACK transmission occurs on a distinct edge.".
-spec step(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
step(Input, State) ->
    case Input#endpoint_rx_input.op of
        tick -> tick(Input, State);
        bind -> bind(Input, observed(Input, State));
        fence -> fence(Input, observed(Input, State))
    end.

%% A stale control request cannot retain admission after the local domain changes.
-spec observed(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_state{}.
observed(Input, State) ->
    case State#endpoint_rx_state.active andalso not local_match(Input, State) of
        true -> close(State);
        false -> State
    end.

%% A remote source is an authorized identity, never a same-clock lifecycle signal.
-spec local_match(#endpoint_rx_input{}, #endpoint_rx_state{}) -> boolean().
local_match(Input, State) ->
    Input#endpoint_rx_input.local_ready andalso
        Input#endpoint_rx_input.local_incarnation =:=
            (State#endpoint_rx_state.binding)#endpoint_binding.destination_incarnation.

%% The receiver is installed first; source admission requires confirmation elsewhere.
-spec bind(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
bind(Input, State) ->
    Binding = Input#endpoint_rx_input.binding,
    Ready =
        Input#endpoint_rx_input.local_ready andalso
            Input#endpoint_rx_input.local_incarnation =:=
                Binding#endpoint_binding.destination_incarnation,
    case Ready of
        false ->
            result(busy, State);
        true ->
            case binding_status(Binding, State#endpoint_rx_state.binding) of
                accepted -> result(accepted, #endpoint_rx_state{binding = Binding, active = true});
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

%% A fence cannot close another namespace, generation or incarnation pair.
-spec fence(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
fence(Input, State) ->
    case Input#endpoint_rx_input.binding =:= State#endpoint_rx_state.binding of
        true -> result(accepted, close(State));
        false -> result(stale, State)
    end.

%% Fault edges perform no handshake; closed steady-state edges absorb stale traffic.
-spec tick(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
tick(Input, State) ->
    case State#endpoint_rx_state.active of
        false ->
            (result(closed, State))#endpoint_rx_output{
                data_ready = true, data_drop = Input#endpoint_rx_input.data_valid
            };
        true ->
            case local_match(Input, State) of
                false -> result(closed, close(State));
                true -> checked_transfer(Input, State)
            end
    end.

%% Current-binding future/premature traffic closes before any ownership transfer.
-spec checked_transfer(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
checked_transfer(Input, State) ->
    Packet = Input#endpoint_rx_input.data_packet,
    Sequence = Packet#endpoint_packet.sequence,
    Current =
        Input#endpoint_rx_input.data_valid andalso
            Packet#endpoint_packet.binding =:= State#endpoint_rx_state.binding,
    Free = not State#endpoint_rx_state.buffered andalso not State#endpoint_rx_state.ack_pending,
    Invalid =
        Current andalso
            (Sequence =:= 0 orelse
                (Sequence > State#endpoint_rx_state.sequence andalso
                    (not Free orelse not next_packet(Packet, State)))),
    case Invalid of
        false ->
            transfer(Input, State);
        true ->
            case Sequence =:= 0 andalso State#endpoint_rx_state.sequence =:= ((1 bsl 32) - 1) of
                true -> result(exhausted, close(State));
                false -> result(invalid, close(State))
            end
    end.

%% The free old slot permits one network capture. Native capture and ACK use old flags.
-spec transfer(#endpoint_rx_input{}, #endpoint_rx_state{}) -> #endpoint_rx_output{}.
transfer(Input, State) ->
    Free = not State#endpoint_rx_state.buffered andalso not State#endpoint_rx_state.ack_pending,
    Current = Free andalso next_packet(Input#endpoint_rx_input.data_packet, State),
    Capture = Input#endpoint_rx_input.data_valid andalso Current,
    DestinationTake =
        State#endpoint_rx_state.buffered andalso Input#endpoint_rx_input.destination_ready,
    Next =
        case Capture of
            true ->
                State#endpoint_rx_state{
                    sequence = State#endpoint_rx_state.sequence + 1, buffered = true
                };
            false ->
                State#endpoint_rx_state{
                    buffered = State#endpoint_rx_state.buffered andalso not DestinationTake,
                    ack_pending =
                        DestinationTake orelse
                            (State#endpoint_rx_state.ack_pending andalso
                                not Input#endpoint_rx_input.ack_tx_ready)
                }
        end,
    #endpoint_rx_output{
        state = Next,
        data_ready = true,
        data_take = Capture,
        data_drop = Input#endpoint_rx_input.data_valid andalso not Current,
        destination_valid = State#endpoint_rx_state.buffered,
        destination_take = DestinationTake,
        ack_valid = State#endpoint_rx_state.ack_pending,
        packet = packet(Next)
    }.

%% Never evaluate a wrapped next sequence; exhaustion cannot admit sequence zero.
-spec next_packet(#endpoint_packet{}, #endpoint_rx_state{}) -> boolean().
next_packet(Packet, State) ->
    case State#endpoint_rx_state.sequence =:= ((1 bsl 32) - 1) of
        true ->
            false;
        false ->
            Packet#endpoint_packet.binding =:= State#endpoint_rx_state.binding andalso
                Packet#endpoint_packet.sequence =:= State#endpoint_rx_state.sequence + 1
    end.

%% Closure abandons local packet ownership but retains binding and sequence tombstones.
-spec close(#endpoint_rx_state{}) -> #endpoint_rx_state{}.
close(State) -> State#endpoint_rx_state{active = false, buffered = false, ack_pending = false}.

%% ACK identity is exactly the last accepted packet, independent of current offers.
-spec packet(#endpoint_rx_state{}) -> #endpoint_packet{}.
packet(State) ->
    #endpoint_packet{
        binding = State#endpoint_rx_state.binding, sequence = State#endpoint_rx_state.sequence
    }.

%% Control and local-failure edges expose no packet handshakes.
-spec result(endpoint_status(), #endpoint_rx_state{}) -> #endpoint_rx_output{}.
result(Status, State) ->
    #endpoint_rx_output{status = Status, state = State, packet = packet(State)}.

-doc "Initializes the optional source service with the same closed native metadata.".
-spec init([]) -> #endpoint_rx_service{}.
init([]) -> #endpoint_rx_service{}.

-doc "Runs one receive-ownership edge and retains its next metadata state.".
-spec handle_call(#endpoint_rx_input{}, #endpoint_rx_service{}) ->
    {reply, #endpoint_rx_output{}, #endpoint_rx_service{}}.
handle_call(Input = #endpoint_rx_input{}, Service) ->
    Output = step(Input, Service#endpoint_rx_service.channel),
    {reply, Output, Service#endpoint_rx_service{channel = Output#endpoint_rx_output.state}}.

-doc "Leaves ownership unchanged; application casts cannot bypass the packet interface.".
-spec handle_cast(#endpoint_rx_unsupported{}, #endpoint_rx_service{}) ->
    {noreply, #endpoint_rx_service{}}.
handle_cast(#endpoint_rx_unsupported{}, Service) -> {noreply, Service}.
