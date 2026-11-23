-module(hls_cross_domain_native).
-moduledoc "Finite native reference for cross-domain mailbox retirement: real source actors, ordinary OTP one_for_all replacement of A/B, and an independent C. It witnesses source behavior and restart scope, not hardware credit safety.".
-behaviour(supervisor).

%% External fixture driver.
-export([native/1]).
%% Ordinary OTP supervisor declaration and its source-actor child start.
-export([init/1, start_actor/3]).

-doc "Runs the matched public source history and writes native-history.etf exclusively after assertions. Source actor generations and failure reasons are retained separately from comparable output history.".
-spec native(file:filename()) -> ok.
native(Stage) ->
    ok = filelib:ensure_dir(filename:join(Stage, "unused")),
    Registry = ets:new(?MODULE, [set, public]),
    {ok, Group} = supervisor:start_link(?MODULE, {Registry, self()}),
    unlink(Group),
    {ok, C} = hls_statem:start_link(hls_domain_counter, [],
        [{mailbox_capacity, 4}, {generation, 1}, {outputs, #{out => self()}}]),
    unlink(C),
    try
        {A, AGeneration} = actor(Registry, a),
        {B, BGeneration} = actor(Registry, b),
        Initial = #{a => command(A, {read, 1, 0}, produced),
            b => command(B, {read, 2, 0}, received),
            c => command(C, {add, 3, 7}, value)},
        #{a := {produced, 1, 0}, b := {received, 2, 0, 0}, c := {value, 3, 7}} = Initial,
        BeforeBurst = burst(A, 10, 3),
        [{received, 10, 3, 1}, {received, 11, 7, 1}] = BeforeBurst,
        BeforeReadouts = #{a => command(A, {read, 12, 0}, produced),
            b => command(B, {read, 13, 0}, received),
            c => command(C, {read, 14, 0}, value)},
        #{a := {produced, 12, 1}, b := {received, 13, 7, 1}, c := {value, 14, 7}} = BeforeReadouts,
        ADown = monitor(process, A),
        BDown = monitor(process, B),
        ok = hls_statem:cast(B, {explode, 20, 0}),
        {hls_statem_failure, {explode, 20, 0}} = BReason = down(BDown, B),
        AReason = down(ADown, A),
        {FreshA, NextA} = replacement(Registry, a, A, 500),
        {FreshB, NextB} = replacement(Registry, b, B, 500),
        true = NextA > AGeneration andalso NextB > BGeneration,
        true = is_process_alive(C),
        %% Old PIDs retain their old identity; sending to them must not reach replacements.
        ok = hls_statem:cast(A, {burst, 90, 99}),
        ok = hls_statem:cast(B, {item, 91, 999}),
        AfterReset = #{a => command(FreshA, {read, 30, 0}, produced),
            b => command(FreshB, {read, 31, 0}, received),
            c => command(C, {read, 32, 0}, value)},
        #{a := {produced, 30, 0}, b := {received, 31, 0, 0}, c := {value, 32, 7}} = AfterReset,
        AfterBurst = burst(FreshA, 40, 5),
        [{received, 40, 5, 1}, {received, 41, 11, 1}] = AfterBurst,
        Independent = [command(C, {add, 50, 2}, value), command(C, {read, 51, 0}, value)],
        [{value, 50, 9}, {value, 51, 9}] = Independent,
        Final = #{a => command(FreshA, {read, 52, 0}, produced),
            b => command(FreshB, {read, 53, 0}, received)},
        #{a := {produced, 52, 1}, b := {received, 53, 11, 1}} = Final,
        History = #{initial => Initial, before_burst => BeforeBurst,
            before_readouts => BeforeReadouts, after_reset => AfterReset,
            after_burst => AfterBurst, independent_c => Independent, final => Final},
        Evidence = #{passed => true, evidence => finite_native_source_witness,
            history => History, generations => #{a => [AGeneration, NextA], b => [BGeneration, NextB], c => [1, 1]},
            failure_reasons => #{a => AReason, b => BReason},
            restart_policy => one_for_all, restarted => [a, b], unaffected => [c],
            limitations => <<"Native ERTS routing has no delayed hardware data/credit injection; RTL owns that separate witness.">>},
        ok = file:write_file(filename:join(Stage, "native-history.etf"),
            term_to_binary(Evidence), [exclusive])
    after
        stop(Group), stop(C), ets:delete(Registry)
    end.

-doc "Starts B before A under ordinary one_for_all; each A binds the exact B PID from the same restart generation.".
-spec init({ets:tid(), pid()}) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Registry, Observer}) ->
    Children = [#{id => Id, start => {?MODULE, start_actor, [Id, Registry, Observer]},
        restart => permanent, shutdown => 5000, type => worker} || Id <- [b, a]],
    {ok, {#{strategy => one_for_all, intensity => 2, period => 60}, Children}}.

-doc "Starts a real hls_statem child and records its fresh mailbox generation. The registry is fixture wiring only and carries no application messages.".
-spec start_actor(a | b, ets:tid(), pid()) -> {ok, pid()} | {error, term()}.
start_actor(Id, Registry, Observer) ->
    Generation = ets:update_counter(Registry, {generation, Id}, {2, 1}, {{generation, Id}, 0}),
    {Module, Outputs} = case Id of
        b -> {hls_cross_domain_consumer, #{out => Observer}};
        a ->
            {Peer, _} = actor(Registry, b),
            {hls_cross_domain_producer, #{peer => Peer, out => Observer}}
    end,
    case hls_statem:start_link(Module, [], [{mailbox_capacity, 4},
        {generation, Generation}, {outputs, Outputs}]) of
        {ok, Pid} ->
            true = ets:insert(Registry, {Id, Pid, Generation}),
            {ok, Pid};
        Error -> Error
    end.

%% Exact current PID identity is resolved only between bounded public requests.
-spec actor(ets:tid(), a | b) -> {pid(), pos_integer()}.
actor(Registry, Id) ->
    [{Id, Pid, Generation}] = ets:lookup(Registry, Id),
    {Pid, Generation}.

%% The startup poll establishes a real replacement, not a predicted completion time.
-spec replacement(ets:tid(), a | b, pid(), non_neg_integer()) -> {pid(), pos_integer()}.
replacement(_Registry, Id, _Previous, 0) -> error({replacement_timeout, Id});
replacement(Registry, Id, Previous, Remaining) ->
    case actor(Registry, Id) of
        {Previous, _} ->
            receive after 10 -> replacement(Registry, Id, Previous, Remaining - 1) end;
        {Pid, _} = Current ->
            true = is_process_alive(Pid),
            Current
    end.

%% The source schedules all three entries internally; the driver sends only one trigger.
-spec burst(pid(), non_neg_integer(), non_neg_integer()) -> [tuple()].
burst(Actor, Request, Value) ->
    ok = hls_statem:admit_cast(Actor, {burst, Request, Value}),
    [report(received, Request), report(received, Request + 1)].

%% Acknowledged native admission uses the same source message tuple as the hardware ingress.
-spec command(pid(), tuple(), atom()) -> tuple().
command(Actor, Message, Tag) ->
    ok = hls_statem:admit_cast(Actor, Message),
    report(Tag, element(2, Message)).

%% Consume the next report rather than selectively hiding an out-of-order publication.
-spec report(atom(), non_neg_integer()) -> tuple().
report(Tag, Request) ->
    receive
        {'$gen_cast', Message} ->
            Tag = element(1, Message),
            Request = element(2, Message),
            Message
    after 5000 -> error({report_timeout, Tag, Request}) end.

%% Exact monitor references distinguish actor failure from group-driven sibling shutdown.
-spec down(reference(), pid()) -> term().
down(Ref, Pid) ->
    receive {'DOWN', Ref, process, Pid, Reason} -> Reason
    after 5000 -> error({actor_not_retired, Pid}) end.

%% Cleanup tolerates a group already terminated by a failed witness assertion.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid, normal, 5000), ok.
