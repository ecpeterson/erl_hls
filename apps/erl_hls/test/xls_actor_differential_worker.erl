-module(xls_actor_differential_worker).
-moduledoc "Runs generated actors through the CPU runtime and ordinary XLS actor lowering for finite differential tests.".

%% Isolated command-line oracle used by tools/actor_differential.py.
-export([main/0]).

-doc "Reads one JSON request, writes its BEAM observations and generated actor, then exits.".
-spec main() -> no_return().
main() ->
    process_flag(trap_exit, true),
    logger:set_primary_config(level, none),
    true = register(xls_actor_differential_oracle, self()),
    [RequestPath] = init:get_plain_arguments(),
    {ok, Bytes} = file:read_file(RequestPath),
    Request = json:decode(Bytes),
    Result = try prepare(Request)
    catch Class:Reason:Stack ->
        #{status => error, class => Class, reason => text(Reason), stack => text(Stack)}
    end,
    ok = file:write_file(maps:get(<<"output">>, Request), json:encode(Result)),
    halt().

%% Compile the actual Erlang actor; the oracle never interprets generated source syntax.
-spec prepare(map()) -> map().
prepare(#{<<"source">> := Source, <<"dslx">> := Dslx, <<"program">> := Program}) ->
    case compile:file(binary_to_list(Source), [binary, return_errors, return_warnings]) of
        {ok, Module, Beam, _Warnings} ->
            {module, Module} = code:load_binary(Module, binary_to_list(Source), Beam),
            {Observations, Last} = lists:mapfoldl(
                fun(Segment, State) -> segment(Module, Segment, State) end,
                #{pid => none, snapshot => #{}}, maps:get(<<"segments">>, Program)),
            stop(maps:get(pid, Last)),
            ok = file:write_file(Dslx, xls_parse:to_xls(binary_to_list(Source))),
            #{status => ok, segments => Observations};
        Error -> #{status => invalid_source, reason => text(Error)}
    end.

%% A checkpoint follows the runtime's synchronous drain of all eligible casts.
-spec segment(module(), map(), map()) -> {map(), map()}.
segment(Module, #{<<"reset">> := Reset, <<"commands">> := Commands}, State0) ->
    State = case Reset of
        true ->
            stop(maps:get(pid, State0)),
            flush(),
            {ok, PID0} = hls_statem:start_link(Module, [], [
                {mailbox_capacity, 3}, {outputs, #{left => self(), right => self(), extra => self()}}]),
            #{pid => PID0, snapshot => #{}};
        false -> State0
    end,
    #{pid := PID, snapshot := Previous} = State,
    Snapshot = case is_process_alive(PID) of
        true ->
            [hls_statem:cast(PID, {command, Kind, Value}) || [Kind, Value] <- Commands],
            try hls_statem:info(PID) of
                #{phase := Phase, data := {cell, Value}, postponed := Postponed} ->
                    #{phase => phase(Phase), value => Value, postponed => Postponed, failure => 0}
            catch exit:_ -> terminated()
            end;
        false -> Previous
    end,
    Events = events([]),
    {Snapshot#{events => Events}, State#{snapshot := Snapshot}}.

%% A callback exception retains the runtime's preceding committed state.
-spec terminated() -> map().
terminated() ->
    receive
        {terminated, Reason, Phase, {cell, Value}} ->
            #{phase => phase(Phase), value => Value, postponed => 0, failure => failure(Reason)}
    after 5000 -> error(missing_termination_observation)
    end.

%% The generated fixture uses a badmatch; any unrelated runtime failure rejects the oracle.
-spec failure(term()) -> 2.
failure({{badmatch, false}, _Stack}) -> 2;
failure(Reason) -> error({unexpected_actor_failure, Reason}).

%% All named output ports reach this process; payload markers retain their source port identity.
-spec events([[integer()]]) -> [[integer()]].
events(Acc) ->
    receive
        {'$gen_cast', {output, Port, Value}} -> events([[Port, Value] | Acc]);
        {'EXIT', _, _} -> events(Acc)
    after 0 -> lists:reverse(Acc)
    end.

%% Phase numbering follows the fixture's explicit declaration order.
-spec phase(quiet | busy) -> 0 | 1.
phase(quiet) -> 0;
phase(busy) -> 1.

%% Stop each old incarnation before constructing the next; reset is a test boundary.
-spec stop(none | pid()) -> ok.
stop(none) -> ok;
stop(PID) ->
    case is_process_alive(PID) of
        true -> ok = hls_statem:stop(PID);
        false -> ok
    end.

%% Discard only diagnostic messages from the retired CPU incarnation.
-spec flush() -> ok.
flush() ->
    receive _ -> flush() after 0 -> ok end.

%% Preserve the complete exception text in the retained failure report.
-spec text(term()) -> binary().
text(Value) -> iolist_to_binary(io_lib:format("~tp", [Value])).
