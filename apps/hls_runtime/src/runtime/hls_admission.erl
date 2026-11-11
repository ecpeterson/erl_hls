-module(hls_admission).
-moduledoc """
Admission observations shared by native actors and hardware endpoints. Admission
releases transport credit; the ordinary gen_server reply still completes a call.
Capacity waits retain no application message and reserve no slot. A wakeup permits
a fresh attempt only after an explicit busy result proved non-admission.
""".
-export([notify/2, wait/3, ready/2, down/2]).
-export_type([waiters/0]).

-doc "At most 32 monitored capacity observers, one outstanding wait per caller process.".
-type waiters() :: #{pid() => {gen_server:from(), reference()}}.

-doc "Sends admission from the actor endpoint before any reply or terminal signal; none opts out.".
-spec notify(gen_server:from() | none, reference() | none) -> ok.
notify(none, _) ->
    ok;
notify(_, none) ->
    ok;
notify({Pid, _}, Token) ->
    Pid ! {hls_admitted, self(), Token},
    ok.

-doc "Answers immediately when room exists; otherwise retains one bounded, monitored observer. It never owns or retries application work.".
-spec wait(gen_server:from(), boolean(), waiters()) -> waiters().
wait(From, true, Waiters) ->
    gen_server:reply(From, ok),
    Waiters;
wait({Pid, _} = From, false, Waiters) when map_size(Waiters) < 32, not is_map_key(Pid, Waiters) ->
    Waiters#{Pid => {From, monitor(process, Pid)}};
wait(From, false, Waiters) ->
    gen_server:reply(From, {error, busy}),
    Waiters.

-doc "Wakes all observers when capacity becomes available; competing callers must still obtain admission.".
-spec ready(boolean(), waiters()) -> waiters().
ready(false, Waiters) ->
    Waiters;
ready(true, Waiters) ->
    maps:foreach(
        fun(_, {From, Ref}) ->
            demonitor(Ref, [flush]),
            gen_server:reply(From, ok)
        end,
        Waiters
    ),
    #{}.

-doc "Forgets a dead observer without treating its abandoned wait as cancellation of application work.".
-spec down(reference(), waiters()) -> {boolean(), waiters()}.
down(Ref, Waiters) ->
    Rest = maps:filter(fun(_, {_, Monitor}) -> Monitor =/= Ref end, Waiters),
    {map_size(Rest) =/= map_size(Waiters), Rest}.
