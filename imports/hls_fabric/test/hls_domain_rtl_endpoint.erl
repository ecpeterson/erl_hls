-module(hls_domain_rtl_endpoint).
-moduledoc "Incarnation-specific application endpoint for the local recovery RTL witness only.".
-behaviour(gen_server).
%% The fixture backend creates and retires these ordinary monitored endpoints.
-export([start/2]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-doc "Starts an unlinked endpoint whose requests carry one immutable hardware incarnation.".
-spec start(pid(), pos_integer()) -> gen_server:start_ret().
start(Backend, Incarnation) -> gen_server:start(?MODULE, {Backend, Incarnation}, []).

-doc "Monitors the backend separately from hardware source failure.".
-spec init({pid(), pos_integer()}) -> {ok, map()}.
init({Backend, Incarnation}) ->
    {ok, #{backend => Backend, incarnation => Incarnation, monitor => monitor(process, Backend), pending => #{}}}.

-doc "Queues ordinary calls or explicitly acknowledged casts under a finite pending bound.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
%% Bounded managed-node casts acknowledge actual hardware ingress admission.
handle_call({'$hls_domain_cast', Request}, From, State) -> issue(cast, Request, From, State);
%% Calls await the real two-actor network's external report.
handle_call(Request, From, State) -> issue(call, Request, From, State).

-doc "Admits ordinary casts without replay; refusal terminates this observer rather than silently dropping work.".
-spec handle_cast(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
handle_cast(Request, State) ->
    case issue(cast, Request, none, State) of
        {reply, Reason, Next} -> {stop, {cast_not_admitted, Reason}, Next};
        {noreply, _} = Result -> Result
    end.

-doc "Resolves exact request references or retires on backend transport loss.".
-spec handle_info(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
%% Reply delivery and endpoint death originate here, preserving ordering for remote node adapters.
handle_info({rtl_result, Ref, Result}, State = #{pending := Pending}) ->
    case maps:take(Ref, Pending) of
        {none, Rest} ->
            case Result of ok -> {noreply, State#{pending := Rest}}; _ -> {stop, {cast_not_admitted, Result}, State} end;
        {From, Rest} -> gen_server:reply(From, Result), {noreply, State#{pending := Rest}};
        error -> {noreply, State}
    end;
%% Retirement follows already-delivered results in the backend's ordered message lane.
handle_info({rtl_retire, Backend, Reason}, State = #{backend := Backend}) ->
    {stop, Reason, State};
%% Unknown transport outcome is not reclassified as a callback failure.
handle_info({'DOWN', Ref, process, _Backend, _Reason}, State = #{monitor := Ref}) ->
    {stop, noconnection, State};
%% Stale responses cannot bind a later request or incarnation.
handle_info(_Message, State) -> {noreply, State}.

%% This fixture exposes the counter's public command vocabulary; serialization belongs to its backend.
-spec issue(call | cast, term(), gen_server:from() | none, map()) -> {reply, term(), map()} | {noreply, map()}.
issue(_Mode, _Request, _From, State = #{pending := Pending}) when map_size(Pending) >= 8 ->
    {reply, {error, busy}, State};
issue(Mode, Request, From, State = #{backend := Backend, incarnation := Incarnation, pending := Pending}) ->
    case Request of
        {add, Value} when is_integer(Value), Value >= 0, Value < (1 bsl 32) -> submit(Mode, Request, From, Backend, Incarnation, Pending, State);
        read -> submit(Mode, Request, From, Backend, Incarnation, Pending, State);
        explode -> submit(Mode, Request, From, Backend, Incarnation, Pending, State);
        _ -> {reply, {error, unsupported_request}, State}
    end.

%% No spawned reply helper can race with the endpoint's own DOWN signal.
-spec submit(call | cast, term(), gen_server:from() | none, pid(), pos_integer(), map(), map()) -> {noreply, map()}.
submit(Mode, Request, From, Backend, Incarnation, Pending, State) ->
    Ref = make_ref(),
    gen_server:cast(Backend, {application, self(), Ref, Incarnation, Mode, Request}),
    {noreply, State#{pending := Pending#{Ref => From}}}.
