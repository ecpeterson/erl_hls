-module(hls_node_connections).
-moduledoc """
The per-node supervisor owns this dynamic connection supervisor. Acceptors and the local carrier start hls_node_connection children here; a failed node retires the whole tree.
""".
-behaviour(supervisor).
%% Connection-child lifecycle.
-export([start_link/0, start/3]).
%% Supervisor callbacks.
-export([init/1]).

-doc "Starts an empty connection supervisor.".
-spec start_link() -> supervisor:startlink_ret().
start_link() -> supervisor:start_link(?MODULE, []).
-doc "Starts a connection that will not restart after disconnection.".
-spec start(pid(), pid(), hls_node_connection:carrier()) -> supervisor:startchild_ret().
start(Sup, Manager, Socket) ->
    supervisor:start_child(Sup, #{
        id => make_ref(),
        start => {hls_node_connection, start_link, [Manager, Socket]},
        restart => temporary
    }).
-doc "Defines independent, temporary connection children.".
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) -> {ok, {#{strategy => one_for_one}, []}}.
