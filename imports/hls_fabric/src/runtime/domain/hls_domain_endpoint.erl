-module(hls_domain_endpoint).
-moduledoc """
An ordinary ERTS endpoint for one actor in one hardware-domain incarnation.
Created by hls_domain_fabric, it preserves admission, reply and termination ordering
for local clients and hls_node. Calls and casts have independent finite capacity,
so held callers cannot prevent a release cast. It never follows a replacement.
""".
-behaviour(gen_server).
%% Backend-owned endpoint lifetime.
-export([start/4]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% An observer retains completion ownership; transport tokens observe admission separately.
-type pending() :: #{
    from := gen_server:from() | none,
    token := reference() | none,
    mode := call | cast
}.
%% Cast capacity is independent of the actor's declared retained-call capacity.
-type limits() :: #{cast := pos_integer(), call := non_neg_integer()}.
-record(endpoint, {
    backend :: pid(),
    monitor :: reference(),
    actor :: term(),
    incarnation :: hls_nums:u64(),
    limits :: limits(),
    pending = #{} :: #{reference() => pending()},
    capacity_waiters = #{} :: hls_admission:waiters()
}).

-doc "Starts an unlinked endpoint with independent cast/call bounds; the backend explicitly retires it.".
-spec start(pid(), term(), hls_nums:u64(), limits()) -> gen_server:start_ret().
start(Backend, Actor, Incarnation, Limits) ->
    gen_server:start(?MODULE, {Backend, Actor, Incarnation, Limits}, []).

-doc "Monitors the backend without issuing any device operation.".
-spec init({pid(), term(), hls_nums:u64(), limits()}) -> {ok, #endpoint{}}.
init({Backend, Actor, Incarnation, Limits}) ->
    {ok, #endpoint{
        backend = Backend,
        monitor = monitor(process, Backend),
        actor = Actor,
        incarnation = Incarnation,
        limits = Limits
    }}.

-doc "Submits typed calls/casts; transport admission is separate from eventual reply completion.".
-spec handle_call(term(), gen_server:from(), #endpoint{}) ->
    {reply, term(), #endpoint{}} | {noreply, #endpoint{}}.
%% The same reserved request is implemented by native source actors.
handle_call({'$hls_submit', Token, Mode, Message}, From, State) when
    is_reference(Token), (Mode =:= call orelse Mode =:= cast)
->
    issue(Mode, Message, From, Token, State);
%% Capacity observers retain no application work; a wakeup is not a slot reservation.
handle_call('$hls_capacity', From, State = #endpoint{capacity_waiters = Waiters}) ->
    {noreply, State#endpoint{
        capacity_waiters = hls_admission:wait(From, available(cast, State), Waiters)
    }};
%% Acknowledged local casts use the common admission path without a transport observer.
handle_call({'$hls_domain_cast', Message}, From, State) ->
    issue(cast, Message, From, none, State);
%% Ordinary calls complete only with a typed reply, never their ingress acknowledgement.
handle_call(Message, From, State) ->
    issue(call, Message, From, none, State).

-doc "Submits ordinary casts; an unreported rejection terminates this endpoint rather than silently losing work.".
-spec handle_cast(term(), #endpoint{}) -> {noreply, #endpoint{}} | {stop, term(), #endpoint{}}.
handle_cast(Message, State) ->
    case issue(cast, Message, none, none, State) of
        {reply, Reason, Next} -> {stop, {cast_not_admitted, Reason}, Next};
        {noreply, _} = Result -> Result
    end.

-doc "Delivers ordered admission/results/effects and retirement; abandons capacity observers whose callers died.".
-spec handle_info(term(), #endpoint{}) -> {noreply, #endpoint{}} | {stop, term(), #endpoint{}}.
%% Hardware admission frees transport credit while a call still owns its reply slot.
handle_info(
    {domain_admitted, Backend, Ref}, State = #endpoint{backend = Backend, pending = Pending}
) ->
    case maps:find(Ref, Pending) of
        {ok, #{from := From, token := Token} = Entry} ->
            hls_admission:notify(From, Token),
            {noreply, State#endpoint{pending = Pending#{Ref := Entry#{token := none}}}};
        error ->
            {noreply, State}
    end;
%% Replies and following retirement originate from the same backend sender.
handle_info(
    {domain_result, Backend, Ref, Result}, State = #endpoint{backend = Backend, pending = Pending}
) ->
    case maps:take(Ref, Pending) of
        {#{from := From, token := Token, mode := Mode}, Rest} ->
            case Mode =:= cast andalso Result =:= ok of
                true -> hls_admission:notify(From, Token);
                false -> ok
            end,
            Next = State#endpoint{pending = Rest},
            Ready = Next#endpoint{
                capacity_waiters = hls_admission:ready(
                    available(cast, Next), Next#endpoint.capacity_waiters
                )
            },
            case From of
                none when Result =/= ok -> {stop, {cast_not_admitted, Result}, Ready};
                none ->
                    {noreply, Ready};
                _ ->
                    gen_server:reply(From, Result),
                    {noreply, Ready}
            end;
        error ->
            {noreply, State}
    end;
%% The actor endpoint supplies the signal-order boundary for effects and DOWN.
handle_info({domain_effect, Backend, Recipient, Message}, State = #endpoint{backend = Backend}) ->
    gen_server:cast(Recipient, Message),
    {noreply, State};
%% Retirement cannot overtake results/effects already sent by this backend.
handle_info({domain_retire, Backend, Reason}, State = #endpoint{backend = Backend}) ->
    {stop, Reason, State};
%% Backend loss is uncertainty, not a fabricated application exception.
handle_info({'DOWN', Ref, process, _Backend, _Reason}, State = #endpoint{monitor = Ref}) ->
    {stop, noconnection, State};
%% Capacity observers can disappear without cancelling any application request.
handle_info(
    {'DOWN', Ref, process, _Observer, _Reason}, State = #endpoint{capacity_waiters = Waiters}
) ->
    {_, Rest} = hls_admission:down(Ref, Waiters),
    {noreply, State#endpoint{capacity_waiters = Rest}};
%% Unrelated late messages cannot mutate request ownership.
handle_info(_Message, State) ->
    {noreply, State}.

%% Count each mode independently so a full reply book cannot strand a release cast.
-spec available(call | cast, #endpoint{}) -> boolean().
available(Mode, #endpoint{pending = Pending, limits = Limits}) ->
    length([ok || #{mode := M} <- maps:values(Pending), M =:= Mode]) < maps:get(Mode, Limits).

%% Busy is strictly pre-submission: no backend write exists to replay.
-spec issue(call | cast, term(), gen_server:from() | none, reference() | none, #endpoint{}) ->
    {reply, term(), #endpoint{}} | {noreply, #endpoint{}}.
issue(
    Mode,
    Message,
    From,
    Token,
    State = #endpoint{
        backend = Backend,
        actor = Actor,
        incarnation = Incarnation,
        pending = Pending
    }
) ->
    case available(Mode, State) of
        false ->
            {reply, {error, busy}, State};
        true ->
            Ref = make_ref(),
            gen_server:cast(Backend, {application, self(), Ref, Actor, Incarnation, Mode, Message}),
            {noreply, State#endpoint{
                pending = Pending#{Ref => #{from => From, token => Token, mode => Mode}}
            }}
    end.
