-module(hls_node_acceptor).
-moduledoc false.
-export([start_link/1, init/1]).

-doc "Starts the node listener's linked accept loop.".
-spec start_link(pid()) -> {ok, pid()} | {error, term()}.
start_link(Sup) -> proc_lib:start_link(?MODULE, init, [Sup]).
-doc "Acknowledges startup and accepts connections until the listener closes.".
-spec init(pid()) -> no_return().
init(Sup) ->
    %% Acknowledge before querying the parent, which is still starting us.
    proc_lib:init_ack({ok, self()}),
    Manager = hls_node_sup:child(Sup, node),
    Connections = hls_node_sup:child(Sup, connections),
    Listen = gen_server:call(Manager, listener),
    accept(Listen, Manager, Connections).

%% Give each accepted socket to a supervised connection; listener failure stops this loop.
-spec accept(gen_tcp:socket(), pid(), pid()) -> no_return().
accept(Listen, Manager, Connections) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} -> attach(Socket, Manager, Connections), accept(Listen, Manager, Connections);
        {error, closed} -> exit(shutdown);
        {error, Reason} -> exit({accept, Reason})
    end.

%% Transfer socket ownership before allowing the connection to read its handshake.
-spec attach(gen_tcp:socket(), pid(), pid()) -> ok.
attach(Socket, Manager, Connections) ->
    case hls_node_connections:start(Connections, Manager, Socket) of
        {ok, Pid} ->
            ok = gen_tcp:controlling_process(Socket, Pid),
            Pid ! connected;
        {error, _} -> gen_tcp:close(Socket)
    end.
