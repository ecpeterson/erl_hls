-module(hls_domain_lifecycle).
-moduledoc """
Finite lifecycle decisions shared by an ERTS domain owner and compiled control logic.

The owner supplies non-reused activation identities and serializes management. This
kernel requests work; the backend establishes the actual fence, reset and setup
completion. Only matching acknowledgements advance those phases. Cold start is
unbound, and timeout never supplies an acknowledgement.

Fence/reset/initialize are level requests. An adapter starts each phase once per
transition and acknowledges completion; observing the same request again must not
pulse another reset. A source fault closes admission, but establishes no fence.
The fault field is a domain-cause identifier, not a compiler source-site code;
source details remain in endpoint diagnostics. The last transition remains
queryable until a new one replaces it. Runtime
attachment, persistent identity allocation and transport authority are outside this
bounded state value.
""".
-behaviour(hls_gs).
-hls_data(controller_state).
-hls_tags([domain_input, domain_output, unsupported_cast]).
-hls_replies([{domain_input, [domain_output]}]).

-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Optional compiler entry: the same local functions run on ERTS and in hardware.
-export([init/1, handle_call/2, handle_cast/2]).

%% The serialized service state wraps the internal lifecycle value without changing it.
-record(controller_state, {lifecycle = #domain_state{} :: #domain_state{}}).
%% The generated controller accepts management calls only; accidental casts fail.
-record(unsupported_cast, {unused = 0 :: hls_nums:u32()}).

%% Shared finite transition and admission interface.
-export([new/0, step/2, action/1, admitted/2]).

%% Public finite values exchanged with adapters and generated wrappers.
-export_type([state/0, input/0, output/0]).

-doc "One domain's current incarnation, first fault and live/last management transition.".
-type state() :: #domain_state{}.

-doc "A bounded management command, correlated completion indication or source fault.".
-type input() :: #domain_input{}.

-doc "The management disposition, current work request, admission gate and next state.".
-type output() :: #domain_output{}.

-doc "Returns a cold, unbound domain which admits no application traffic.".
-spec new() -> #domain_state{}.
new() -> #domain_state{}.

-doc "Applies one management input; rejected or stale commands leave state unchanged. Identity fields are trusted unsigned 64-bit values; zero targets/transitions and non-increasing activation targets reject. Completion indications must echo all three accepted identity fields.".
-spec step(#domain_input{}, #domain_state{}) -> #domain_output{}.
step(Input, State) ->
    case Input#domain_input.op of
        ?HLS_DOMAIN_INSPECT -> output(?HLS_DOMAIN_OK, State);
        ?HLS_DOMAIN_ACTIVATE -> request(Input, State);
        ?HLS_DOMAIN_REPLACE -> request(Input, State);
        ?HLS_DOMAIN_FAULT -> fault(Input, State);
        ?HLS_DOMAIN_FENCED -> completion(Input, State);
        ?HLS_DOMAIN_RESET_DONE -> completion(Input, State);
        ?HLS_DOMAIN_INITIALIZED -> completion(Input, State);
        ?HLS_DOMAIN_ABORT -> abort(Input, State);
        _ -> output(?HLS_DOMAIN_INVALID, State)
    end.

-doc "Returns the outstanding phase-level backend request; failed/unbound/ready states request no physical action.".
-spec action(#domain_state{}) -> hls_nums:uN(3).
action(State) ->
    case State#domain_state.phase of
        ?HLS_DOMAIN_CLOSING -> ?HLS_DOMAIN_FENCE;
        ?HLS_DOMAIN_ISOLATED -> ?HLS_DOMAIN_RESET;
        ?HLS_DOMAIN_INITIALIZING -> ?HLS_DOMAIN_INITIALIZE;
        _ -> ?HLS_DOMAIN_NONE
    end.

-doc "Admits an application event only for the current nonzero ready incarnation.".
-spec admitted(hls_nums:u64(), #domain_state{}) -> boolean().
admitted(Activation, State) ->
    State#domain_state.phase =:= ?HLS_DOMAIN_READY andalso
        Activation =/= 0 andalso Activation =:= State#domain_state.current.

%% A repeated transition observes its current result without allocating another successor.
-spec request(#domain_input{}, #domain_state{}) -> #domain_output{}.
request(Input, State) ->
    case same_transition(Input, State) of
        true -> output(?HLS_DOMAIN_REPLAY, State);
        false -> new_request(Input, State)
    end.

%% Expected incarnation and lifecycle phase are checked before reserving a new target.
-spec new_request(#domain_input{}, #domain_state{}) -> #domain_output{}.
new_request(Input, State) ->
    case Input#domain_input.expected =:= State#domain_state.current of
        false ->
            output(?HLS_DOMAIN_STALE, State);
        true ->
            case live_phase(State#domain_state.phase) of
                true -> output(?HLS_DOMAIN_BUSY, State);
                false -> admit_request(Input, State)
            end
    end.

%% Only cold activation or explicit replacement of a ready/failed incarnation can start work.
-spec admit_request(#domain_input{}, #domain_state{}) -> #domain_output{}.
admit_request(Input, State) ->
    Activate =
        Input#domain_input.op =:= ?HLS_DOMAIN_ACTIVATE andalso
            (State#domain_state.phase =:= ?HLS_DOMAIN_UNBOUND orelse
                (State#domain_state.phase =:= ?HLS_DOMAIN_FAILED andalso
                    State#domain_state.current =:= 0)),
    Replace =
        Input#domain_input.op =:= ?HLS_DOMAIN_REPLACE andalso
            State#domain_state.current =/= 0 andalso
            (State#domain_state.phase =:= ?HLS_DOMAIN_READY orelse
                State#domain_state.phase =:= ?HLS_DOMAIN_FAILED),
    Valid =
        Input#domain_input.target > State#domain_state.current andalso
            Input#domain_input.target > State#domain_state.target andalso
            Input#domain_input.transition =/= 0,
    case (Activate orelse Replace) andalso Valid of
        false ->
            output(?HLS_DOMAIN_INVALID, State);
        true ->
            Next = State#domain_state{
                phase = ?HLS_DOMAIN_CLOSING,
                previous = State#domain_state.current,
                target = Input#domain_input.target,
                transition = Input#domain_input.transition
            },
            output(?HLS_DOMAIN_ACCEPTED, Next)
    end.

%% Every completion must identify the live operation, including both incarnation endpoints.
-spec completion(#domain_input{}, #domain_state{}) -> #domain_output{}.
completion(Input, State) ->
    case same_transition(Input, State) of
        false -> output(?HLS_DOMAIN_STALE, State);
        true -> advance(Input#domain_input.op, State)
    end.

%% Fencing is an acknowledgement from the backend, never an elapsed-time inference.
-spec advance(hls_nums:uN(4), #domain_state{}) -> #domain_output{}.
advance(?HLS_DOMAIN_FENCED, State = #domain_state{phase = ?HLS_DOMAIN_CLOSING}) ->
    output(?HLS_DOMAIN_OK, State#domain_state{phase = ?HLS_DOMAIN_ISOLATED});
%% Reset installs the new incarnation but does not open application admission.
advance(?HLS_DOMAIN_RESET_DONE, State = #domain_state{phase = ?HLS_DOMAIN_ISOLATED}) ->
    output(?HLS_DOMAIN_OK, State#domain_state{
        phase = ?HLS_DOMAIN_INITIALIZING,
        current = State#domain_state.target,
        fault = 0
    });
%% Only the complete initialization acknowledgement publishes readiness.
advance(?HLS_DOMAIN_INITIALIZED, State = #domain_state{phase = ?HLS_DOMAIN_INITIALIZING}) ->
    Next = State#domain_state{phase = ?HLS_DOMAIN_READY},
    Result = output(?HLS_DOMAIN_COMPLETED, Next),
    Result#domain_output{action = ?HLS_DOMAIN_PUBLISH};
%% A duplicate or out-of-order acknowledgement cannot advance a different phase.
advance(_Operation, State) ->
    output(?HLS_DOMAIN_STALE, State).

%% First current-incarnation fault wins; retiring old actors cannot reopen admission.
-spec fault(#domain_input{}, #domain_state{}) -> #domain_output{}.
fault(Input, State) ->
    Current = State#domain_state.current,
    case
        Current =/= 0 andalso Input#domain_input.expected =:= Current andalso
            Input#domain_input.fault =/= 0
    of
        false ->
            output(?HLS_DOMAIN_STALE, State);
        true ->
            FirstFault = first_fault(State#domain_state.fault, Input#domain_input.fault),
            Phase =
                case State#domain_state.phase of
                    ?HLS_DOMAIN_READY -> ?HLS_DOMAIN_FAILED;
                    ?HLS_DOMAIN_INITIALIZING -> ?HLS_DOMAIN_FAILED;
                    Existing -> Existing
                end,
            output(?HLS_DOMAIN_FAILURE, State#domain_state{phase = Phase, fault = FirstFault})
    end.

%% A failed management operation stays closed; even an expired deadline cannot undo replacement.
-spec abort(#domain_input{}, #domain_state{}) -> #domain_output{}.
abort(Input, State) ->
    case
        same_transition(Input, State) andalso live_phase(State#domain_state.phase) andalso
            Input#domain_input.fault =/= 0
    of
        false ->
            output(?HLS_DOMAIN_STALE, State);
        true ->
            FirstFault = first_fault(State#domain_state.fault, Input#domain_input.fault),
            output(?HLS_DOMAIN_FAILURE, State#domain_state{
                phase = ?HLS_DOMAIN_FAILED, fault = FirstFault
            })
    end.

%% All fields identify the single retained transition; the all-zero cold record is not one.
-spec same_transition(#domain_input{}, #domain_state{}) -> boolean().
same_transition(Input, State) ->
    State#domain_state.transition =/= 0 andalso
        Input#domain_input.expected =:= State#domain_state.previous andalso
        Input#domain_input.target =:= State#domain_state.target andalso
        Input#domain_input.transition =:= State#domain_state.transition.

%% These phases retain a pending physical operation and exclude conflicting requests.
-spec live_phase(hls_nums:uN(3)) -> boolean().
live_phase(Phase) ->
    Phase =:= ?HLS_DOMAIN_CLOSING orelse Phase =:= ?HLS_DOMAIN_ISOLATED orelse
        Phase =:= ?HLS_DOMAIN_INITIALIZING.

%% Preserve the first observation until a confirmed reset installs a new incarnation.
-spec first_fault(hls_nums:u16(), hls_nums:u16()) -> hls_nums:u16().
first_fault(0, Incoming) -> Incoming;
first_fault(Existing, _Incoming) -> Existing.

%% Admission and requested work are derived from one state value rather than cached separately.
-spec output(hls_nums:uN(4), #domain_state{}) -> #domain_output{}.
output(Status, State) ->
    #domain_output{
        status = Status,
        action = action(State),
        admit = admitted(State#domain_state.current, State),
        state = State
    }.

-doc "Initializes the optional compilable service adapter; ordinary callers may use new/0 directly.".
-spec init([]) -> #controller_state{}.
init([]) -> #controller_state{lifecycle = new()}.

-doc "Applies the same local lifecycle kernel when compiled as a hardware control service.".
-spec handle_call(#domain_input{}, #controller_state{}) ->
    {reply, #domain_output{}, #controller_state{}}.
handle_call(Input = #domain_input{}, State) ->
    Output = step(Input, State#controller_state.lifecycle),
    {reply, Output, State#controller_state{lifecycle = Output#domain_output.state}}.

-doc "Fails accidental cast invocation; the domain wrapper calls only the management interface.".
-spec handle_cast(#unsupported_cast{}, #controller_state{}) -> {noreply, #controller_state{}}.
handle_cast(#unsupported_cast{unused = Value}, State) ->
    false = Value =:= Value,
    {noreply, State}.
