-module(snowflake_barrier_tests).
-moduledoc "Complete-set, rejection and publication checks for the ordinary completion barrier.".
-compile({parse_transform, hls_pack}).
-hls_data(barrier).
-export([write_dslx/1]).
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_actor_protocol.hrl").
-include("snowflake_barrier.hrl").

-doc "Writes the normally lowered barrier with entry-publication backpressure witnesses.".
-spec write_dslx(file:filename()) -> ok.
write_dslx(Path) ->
    {ok, Tests} = file:read_file(filename:join([code:lib_dir(hls_snowflake), "test", "snowflake_barrier_tests.inc.x"])),
    file:write_file(Path,
        [xls_parse:to_xls(filename:join([code:lib_dir(hls_snowflake), "src", "snowflake_barrier.erl"]),
            #{source_options => [{i, filename:join(code:lib_dir(hls_snowflake), "include")}]}), Tests]).

%% Early readiness waits for configuration and cannot replace the last missing member.
-spec early_startup_test() -> ok.
early_startup_test() ->
    with_actor(fun(Pid) ->
        lists:foreach(fun(Source) -> hls_statem:cast(Pid, #sf_ready{source = Source}) end,
            [16, 12, 15, 13, 17]),
        ?assertEqual(5, maps:get(postponed, hls_statem:info(Pid))),
        hls_statem:cast(Pid, config(12, 6)),
        quiet(Pid),
        hls_statem:cast(Pid, #sf_ready{source = 14}),
        ?assertEqual(#sf_ready{source = 2}, message())
    end).

%% Reordered contributions retain every busy bit and publish once per complete epoch.
-spec reordered_epochs_test() -> ok.
reordered_epochs_test() ->
    with_actor(fun(Pid) ->
        start(Pid, 12, 6),
        lists:foreach(fun(Epoch) ->
            Kind = lists:nth(Epoch + 1, [0, 1, 2, 2, 3, 4, 0, 1]),
            Sources = lists:seq(12, 17),
            {Front, Back} = lists:split(Epoch rem 6, Sources),
            Order = Back ++ Front,
            lists:foreach(fun(Source) ->
                send_done(Pid, Source, Epoch, Kind, Epoch rem 2 =:= 0 andalso Source =:= 15),
                quiet(Pid)
            end, lists:sublist(Order, 5)),
            send_done(Pid, lists:last(Order), Epoch, Kind,
                Epoch rem 2 =:= 0 andalso lists:last(Order) =:= 15),
            ?assertEqual(#sf_done{source = 2, epoch = Epoch, kind = Kind,
                busy = Epoch rem 2 =:= 0}, message()),
            quiet(Pid)
        end, lists:seq(0, 7))
    end).

%% A singleton at the last source identity exercises the interval's nonwrapping upper bound.
-spec last_source_test() -> ok.
last_source_test() ->
    with_actor(fun(Pid) ->
        start(Pid, 255, 1),
        send_done(Pid, 255, 0, 0, false),
        ?assertEqual(#sf_done{source = 2, epoch = 0, kind = 0, busy = false}, message())
    end).

%% Empty, oversized and overflowing source intervals never become active groups.
-spec invalid_config_test_() -> [fun(() -> ok)].
invalid_config_test_() ->
    [fun() -> with_actor(fun(Pid) ->
        fails(Pid, [Config], {badmatch, false})
    end) end || Config <- [config(0, 0), config(0, 7), config(252, 6)]].

%% Startup requires distinct members from the configured source interval.
-spec invalid_ready_test_() -> [fun(() -> ok)].
invalid_ready_test_() ->
    [fun() -> with_actor(fun(Pid) ->
        hls_statem:cast(Pid, config(12, 6)),
        fails(Pid, [#sf_ready{source = Source} || Source <- Sources], Reason)
    end) end || {Sources, Reason} <- [
        {[12, 12], {badmatch, true}}, {[11], {badmatch, false}}, {[18], {badmatch, false}}]].

%% Bad identities, epochs and kind disagreements cannot satisfy a completion set.
-spec invalid_done_test_() -> [fun(() -> ok)].
invalid_done_test_() ->
    [fun() -> with_actor(fun(Pid) ->
        start(Pid, 12, 6),
        fails(Pid, Messages, Reason)
    end) end || {Messages, Reason} <- [
        {[done(12, 0, 0), done(12, 0, 0)], {badmatch, true}},
        {[done(11, 0, 0)], {badmatch, false}},
        {[done(18, 0, 0)], {badmatch, false}},
        {[done(12, 1, 0)], function_clause},
        {[done(12, 0, 5)], {badmatch, false}},
        {[done(12, 0, 2), done(13, 0, 4)], {badmatch, false}}]].

%% A published epoch cannot be replayed into the freshly cleared member set.
-spec stale_done_test() -> ok.
stale_done_test() ->
    with_actor(fun(Pid) ->
        start(Pid, 12, 1),
        send_done(Pid, 12, 0, 0, false),
        _ = message(),
        fails(Pid, [done(12, 0, 0)], function_clause)
    end).

%% The entry result carries the old tag while its committed successor wraps modulo 2^32.
-spec publication_rollover_test() -> ok.
publication_rollover_test() ->
    Cell = #barrier{source = 2, first = 12, count = 6, received = 6,
        seen = 63, epoch = 16#ffffffff, kind = 4, busy = true},
    {Next, [{cast, status, Message}]} = snowflake_barrier:publishing(enter, collecting, Cell),
    ?assertEqual(#sf_done{source = 2, epoch = 16#ffffffff, kind = 4, busy = true}, Message),
    ?assertEqual(Cell#barrier{epoch = 0, received = 0, seen = 0, busy = false}, Next).

%% The tree's quiet stream checks every full vertex/edge state and retirement through the real topology.
-spec tree_reference_test_() -> term().
tree_reference_test_() ->
    {timeout, 5, fun() -> tree_stream(<<"surface_d3_zero">>, #{}) end}.

%% A delayed vertex perturbs neighbor snapshots and leaf acknowledgments under eight-sheet pressure.
-spec tree_delayed_vertex_test_() -> term().
tree_delayed_vertex_test_() ->
    {timeout, 5, fun() -> tree_stream(<<"surface_d3_burst">>,
        #{input_window => 8, delay_source => {vertex, 0}, delay_ms => 1}) end}.

%% One slow branch cannot allow the root to advance before that branch's full completion set.
-spec tree_delayed_barrier_test_() -> term().
tree_delayed_barrier_test_() ->
    {timeout, 5, fun() -> tree_stream(<<"surface_d3_burst">>,
        #{input_window => 8, delay_source => {barrier, 2}, delay_ms => 1}) end}.

%% The runner checks actual state/edge replicas and every correction; the pinned fixture independently checks phase counts and retirement.
-spec tree_stream(binary(), map()) -> ok.
tree_stream(Name, Options) ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", "surface-named.json"])),
    #{<<"cases">> := Cases} = json:decode(Bytes),
    [#{<<"sheets">> := Sheets}] = [Case || Case = #{<<"name">> := N} <- Cases, N =:= Name],
    Reports = snowflake_actor_run:run(3, 3,
        [maps:get(<<"input_mask">>, Sheet) || Sheet <- Sheets], Options#{barrier => tree6}),
    ?assertEqual(length(Sheets), length(Reports)),
    lists:foreach(fun({Expected, Actual}) ->
        ?assertEqual(maps:get(<<"reference_runtime_all">>, Expected) + 1, maps:get(ticks, Actual)),
        lists:foreach(fun(Field) ->
            ?assertEqual(maps:get(atom_to_binary(Field), Expected), maps:get(Field, Actual))
        end, [retired_sheet, retired_spatial_mask, retired_temporal_mask])
    end, lists:zip(Sheets, Reports)).

%% Exercise the real ERTS behavior, including its postponed mailbox and repeat entries.
-spec with_actor(fun((pid()) -> ok)) -> ok.
with_actor(Fun) ->
    {ok, Pid} = hls_statem:start_link(snowflake_barrier, [],
        [{mailbox_capacity, 8}, {outputs, #{status => self()}}]),
    unlink(Pid),
    try Fun(Pid)
    after
        case is_process_alive(Pid) of true -> hls_statem:stop(Pid); false -> ok end
    end.

%% Source identities remain absolute until the single group result is emitted.
-spec config(non_neg_integer(), pos_integer() | 0) -> #sf_barrier_config{}.
config(First, Count) -> #sf_barrier_config{source = 2, first = First, count = Count}.

%% Start a group through ordinary configuration and readiness messages.
-spec start(pid(), non_neg_integer(), pos_integer()) -> ok.
start(Pid, First, Count) ->
    hls_statem:cast(Pid, config(First, Count)),
    lists:foreach(fun(Source) -> hls_statem:cast(Pid, #sf_ready{source = Source}) end,
        lists:seq(First, First + Count - 1)),
    ?assertEqual(#sf_ready{source = 2}, message()).

%% Construct a quiet acknowledgment for rejection scenarios.
-spec done(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> #sf_done{}.
done(Source, Epoch, Kind) -> #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = false}.

%% Send one contribution through the public behavior interface.
-spec send_done(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) -> ok.
send_done(Pid, Source, Epoch, Kind, Busy) ->
    hls_statem:cast(Pid, (done(Source, Epoch, Kind))#sf_done{busy = Busy}).

%% Synchronize the actor before asserting that no partial result has escaped.
-spec quiet(pid()) -> ok.
quiet(Pid) ->
    _ = hls_statem:info(Pid),
    receive {'$gen_cast', Message} -> error({partial_completion, Message})
    after 0 -> ok
    end.

%% Missing publication fails the test rather than looking like a quiet completion.
-spec message() -> #sf_ready{} | #sf_done{}.
message() ->
    receive {'$gen_cast', Message} -> Message
    after 1000 -> error(missing_barrier_publication)
    end.

%% Check the actual callback error so unrelated actor failures cannot satisfy rejection.
-spec fails(pid(), [#sf_barrier_config{} | #sf_ready{} | #sf_done{}], term()) -> ok.
fails(Pid, Messages, Reason) ->
    Monitor = monitor(process, Pid),
    lists:foreach(fun(Message) -> hls_statem:cast(Pid, Message) end, Messages),
    receive {'DOWN', Monitor, process, Pid, {Actual, _Stack}} -> ?assertEqual(Reason, Actual)
    after 1000 -> error(invalid_completion_accepted)
    end.
