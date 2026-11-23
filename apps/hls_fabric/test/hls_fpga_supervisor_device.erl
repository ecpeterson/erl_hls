-module(hls_fpga_supervisor_device).
-moduledoc "Public-pin RTL test instrument, deliberately separate from the replaceable host management adapter. No lifecycle decision or actor state is implemented here.".
-behaviour(gen_server).
-export([start_link/2, command/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "Starts one real generated-RTL simulator and retains all public command/response observations.".
-spec start_link(file:filename(), file:filename()) -> gen_server:start_ret().
start_link(Binary, Log) -> gen_server:start_link(?MODULE, {Binary, Log}, []).
-doc "Advances or drives public pins using a bounded test command; no internal RTL access is available.".
-spec command(pid(), iodata()) -> map().
command(Device, Command) -> gen_server:call(Device, {command, iolist_to_binary(Command)}, 30000).
-doc "Closes the test port after the finite witness has completed.".
-spec stop(pid()) -> ok.
stop(Device) -> gen_server:stop(Device).
-doc "Keeps the simulator port independent of backend adapter and observer lifetimes.".
-spec init({file:filename(), file:filename()}) -> {ok, map()}.
init({Binary, Log}) ->
    Port = open_port({spawn_executable, Binary}, [binary, {line, 65536}, exit_status, use_stdio]),
    {ok, File} = file:open(Log, [write, exclusive]),
    {ok, #{port => Port, log => File}}.
-doc "Serializes test-pin transactions, never application execution or restart policy.".
-spec handle_call(term(), gen_server:from(), map()) -> term().
%% Every reply is observed from the generated simulator, with a finite instrument deadline.
handle_call({command, Command}, _From, S = #{port := Port, log := File}) ->
    true = port_command(Port, <<Command/binary, "\n">>),
    receive
        {Port, {data, {eol, Bytes}}} ->
            ok = io:format(File, "~s\n~s\n", [Command, Bytes]),
            {reply, json:decode(Bytes), S};
        {Port, {exit_status, Code}} -> error({simulator_exit, Code})
    after 20000 -> error(simulator_timeout)
    end.
-doc "The instrument has no asynchronous write path.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_, S) -> {noreply, S}.
-doc "An unexpected simulator exit is terminal test failure.".
-spec handle_info(term(), map()) -> term().
%% The child process cannot disappear while leaving an apparently live instrument.
handle_info({Port, {exit_status, Code}}, S = #{port := Port}) -> {stop, {simulator_exit, Code}, S};
%% There are no lifecycle or application messages addressed to the test instrument.
handle_info(_, S) -> {noreply, S}.
-doc "Releases the simulator and evidence descriptor; no device-retirement claim is inferred.".
-spec terminate(term(), map()) -> ok.
terminate(_, #{port := Port, log := File}) ->
    catch port_close(Port), file:close(File), ok.
