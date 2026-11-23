-module(hls_fpga_supervisor_backend).
-moduledoc "Witness-only host adapter for a whole compiled supervisor subtree. Child application ports remain raw; this adapter does not publish autonomously replaced children as distributed PIDs.".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-export([start_link/3, attach/2, status/1, request/3, endpoint/4, send_request/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "Attaches an instrument with retained codecs and an already durably reserved child-identity interval. Starting this adapter never resets hardware.".
-spec start_link(pid(), map(), none | {pos_integer(), pos_integer()}) -> gen_server:start_ret().
start_link(Device, Codecs, Grant) -> gen_server:start_link(?MODULE, {Device, Codecs, Grant}, []).
-doc "Claims local management authority without changing the supervisor incarnation.".
-spec attach(pid(), pid()) -> {ok, reference()} | {error, term()}.
attach(Pid, Owner) -> gen_server:call(Pid, {attach, Owner}).
-doc "Obtains fresh parent controller evidence from actual public pins.".
-spec status(pid()) -> {ok, hls_domain_backend:snapshot()} | {error, term()}.
status(Pid) -> gen_server:call(Pid, status).
-doc "Submits an exact-incarnation request; controller completions come only from hardware.".
-spec request(pid(), reference(), #domain_input{}) -> #domain_output{} | {error, term()}.
request(Pid, Authority, Input) -> gen_server:call(Pid, {request, Authority, Input}).
-doc "Resolves only the parent lifetime observer; no child PID is synthesized.".
-spec endpoint(pid(), reference(), pos_integer(), term()) -> {ok, pid()} | {error, term()}.
endpoint(Pid, Authority, Incarnation, Actor) -> gen_server:call(Pid, {endpoint, Authority, Incarnation, Actor}).
-doc "Preserves the owner caller identity while observing asynchronous management responses.".
-spec send_request(pid(), hls_domain_backend:request()) -> gen_server:request_id().
send_request(Pid, Request) -> gen_server:send_request(Pid, Request).
-doc "Creates only host-side ownership and observation state.".
-spec init({pid(), map(), none | {pos_integer(), pos_integer()}}) -> {ok, map()}.
init({Device, Codecs, Grant}) ->
    erlang:send_after(20, self(), poll),
    {ok, #{device => Device, codecs => Codecs, grant => Grant, owner => undefined,
        authority => undefined, monitor => undefined, actor => none, current => 0,
        snapshot => #{state => #domain_state{}, actors => #{}, fault_reason => none}}}.
-doc "Admits management only from the attached owner; status remains read-only.".
-spec handle_call(term(), gen_server:from(), map()) -> term().
%% Exact repeats preserve the local authority rather than taking over its caller.
handle_call({attach, Owner}, {Owner, _}, S = #{owner := Owner, authority := Ref}) ->
    {reply, {ok, Ref}, S};
%% Local owner death revokes authority but leaves the FPGA supervisor running.
handle_call({attach, Owner}, {Owner, _}, S = #{owner := undefined}) ->
    Ref = make_ref(),
    {reply, {ok, Ref}, S#{owner => Owner, authority => Ref, monitor => monitor(process, Owner)}};
%% Every status answer comes from the public interface rather than a guessed timer.
handle_call(status, _From, S) ->
    {Evidence, Next} = observe(S), {reply, {ok, Evidence}, Next};
%% A pre-reserved interval is bound before the actual parent transition is emitted.
handle_call({request, Ref, Input}, {Owner, _}, S = #{owner := Owner, authority := Ref}) ->
    #{codecs := Codecs, device := Device} = S,
    Data = hls_fpga_supervisor_device:command(Device, io_lib:format("management ~B ~B ~B ~B ~B", [
        encode(operation, Input#domain_input.op, Codecs), Input#domain_input.expected,
        Input#domain_input.target, Input#domain_input.transition,
        encode(fault, Input#domain_input.fault, Codecs)])),
    Disposition = decode(status, maps:get(<<"response_status">>, Data), Codecs),
    GrantResult = case Disposition of
        accepted -> install_grant(Input, S);
        replay -> ok;
        _ -> ok
    end,
    {Evidence, Next} = observe(S),
    case GrantResult of
        ok ->
            Output = #domain_output{status = Disposition,
                action = decode(action, maps:get(<<"response_action">>, Data), Codecs),
                state = maps:get(state, Evidence),
                admit = (maps:get(state, Evidence))#domain_state.phase =:= ready},
            {reply, Output, Next};
        Error -> {reply, Error, Next}
    end;
%% The endpoint is only an incarnation-specific observable lifetime for the host supervisor.
handle_call({endpoint, Ref, Epoch, supervisor}, {Owner, _}, S = #{owner := Owner,
        authority := Ref, current := Epoch, actor := Actor,
        snapshot := #{state := #domain_state{phase = ready}}}) when is_pid(Actor) ->
    {reply, {ok, Actor}, S};
%% No alternate command route bypasses parent ownership or directly controls a child.
handle_call(_, _, S) -> {reply, {error, unauthorized}, S}.
-doc "The adapter has no ordinary application cast path.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_, S) -> {noreply, S}.
-doc "Polls lifecycle evidence and revokes only local authority when the owner dies.".
-spec handle_info(term(), map()) -> {noreply, map()}.
%% Polling cannot allocate identities or request reset/replacement.
handle_info(poll, S) ->
    {_, Next} = observe(S), erlang:send_after(20, self(), poll), {noreply, Next};
%% Lost host reachability leaves hardware and its local clock/restart policy intact.
handle_info({'DOWN', Ref, process, Owner, _}, S = #{monitor := Ref, owner := Owner}) ->
    {noreply, S#{owner => undefined, authority => undefined, monitor => undefined}};
%% Stale host notifications cannot mutate the remote controller.
handle_info(_, S) -> {noreply, S}.
-doc "Adapter loss reports connection uncertainty through its parent endpoint; it never stops the FPGA.".
-spec terminate(term(), map()) -> ok.
terminate(_, S) -> retire(noconnection, S), ok.

%% The deployment reserved these numbers before this adapter was given them; duplicates do not rewind RTL allocation.
-spec install_grant(#domain_input{}, map()) -> ok | {error, term()}.
install_grant(#domain_input{op = Op, target = Epoch}, S = #{device := Device, grant := {First, Last}})
        when Op =:= activate; Op =:= replace ->
    wait_initializing(Device, maps:get(codecs, S), Epoch, 128),
    Data = hls_fpga_supervisor_device:command(Device,
        io_lib:format("grant ~B ~B ~B", [Epoch, First, Last])),
    case maps:get(<<"grant_accepted">>, Data) of true -> ok; false -> {error, grant_rejected} end;
install_grant(#domain_input{op = Op}, #{grant := none}) when Op =:= activate; Op =:= replace ->
    {error, no_delegated_identities};
install_grant(_, _) -> ok.

%% Parent reset/setup must reach the grant boundary; polling does not advance lifecycle itself.
-spec wait_initializing(pid(), map(), pos_integer(), non_neg_integer()) -> ok.
wait_initializing(_Device, _Codecs, _Epoch, 0) -> error(parent_initialization_timeout);
wait_initializing(Device, Codecs, Epoch, Left) ->
    Data = hls_fpga_supervisor_device:command(Device, "snapshot"),
    case {decode(phase, maps:get(<<"domain_phase">>, Data), Codecs), maps:get(<<"domain_current">>, Data)} of
        {initializing, Epoch} -> ok;
        _ -> wait_initializing(Device, Codecs, Epoch, Left - 1)
    end.

%% Enum codecs are retained from the actual Erlang source types used by the compiler.
-spec encode(atom(), atom(), map()) -> non_neg_integer().
encode(Kind, Value, Codecs) ->
    Type = maps:get(Kind, Codecs), Width = hls_type:width(Type),
    <<Bits:Width>> = hls_type:pack(Value, Type), Bits.
%% The inverse mapping avoids a separately maintained host numeric codebook.
-spec decode(atom(), non_neg_integer(), map()) -> atom().
decode(Kind, Bits, Codecs) ->
    Type = maps:get(Kind, Codecs), {Value, <<>>} = hls_type:unpack(<<Bits:(hls_type:width(Type))>>, Type), Value.

%% The simulator clocks all domains while this host observer asks for a snapshot.
-spec observe(map()) -> {hls_domain_backend:snapshot(), map()}.
observe(S = #{device := Device}) -> observation(hls_fpga_supervisor_device:command(Device, "snapshot"), S).
%% Only actual phase transitions create or retire the parent observer endpoint.
-spec observation(map(), map()) -> {hls_domain_backend:snapshot(), map()}.
observation(Data, S = #{codecs := Codecs, current := Previous, actor := Actor}) ->
    State = #domain_state{phase = decode(phase, maps:get(<<"domain_phase">>, Data), Codecs),
        current = maps:get(<<"domain_current">>, Data), previous = maps:get(<<"domain_previous">>, Data),
        target = maps:get(<<"domain_target">>, Data), transition = maps:get(<<"domain_transition">>, Data),
        fault = decode(fault, maps:get(<<"domain_fault">>, Data), Codecs)},
    Epoch = State#domain_state.current,
    Next = case {State#domain_state.phase, Epoch =:= Previous, Actor} of
        {ready, true, Pid} when is_pid(Pid) -> S;
        {ready, _, _} ->
            Closed = retire(shutdown, S),
            Closed#{actor => spawn(fun() -> receive never -> ok end end), current => Epoch};
        {Phase, _, _} when Phase =:= failed; Phase =:= stopped ->
            retire(case Phase of failed -> {domain_failed, State#domain_state.fault}; stopped -> shutdown end, S);
        _ -> S
    end,
    Actors = case maps:get(actor, Next) of none -> #{}; P -> #{supervisor => P} end,
    Evidence = #{state => State, actors => Actors, fault_reason => State#domain_state.fault},
    {Evidence, Next#{snapshot => Evidence}}.
%% The endpoint carries no application state and cannot restart anything by itself.
-spec retire(term(), map()) -> map().
retire(Reason, S = #{actor := Actor}) ->
    case Actor of none -> ok; _ -> exit(Actor, Reason) end, S#{actor => none}.
