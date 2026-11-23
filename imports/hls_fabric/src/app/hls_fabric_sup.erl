-module(hls_fabric_sup).
-moduledoc """
The application callback starts this root supervisor; clients explicitly add or remove hls_node trees over already-open brokers.
""".
-behaviour(supervisor).
%% Application supervision.
-export([start_link/0]).
%% Explicit virtual-node lifecycle.
-export([start_node/4, stop_node/1]).
%% Supervisor callbacks.
-export([init/1]).

-doc "Starts the registered root supervisor.".
-spec start_link() -> supervisor:startlink_ret().
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Device attachment is explicit. Broker/device recovery belongs to the owner
%% of those persistent transports, and is never an automatic open/reset here.
-doc "Activates a named virtual node on existing brokers. Failed nodes are not automatically reactivated.".
-spec start_node(node(), hls_node:brokers(), [hls_node:service()], hls_node:options()) ->
    supervisor:startchild_ret().
start_node(Name, Brokers, Services, Options) ->
    supervisor:start_child(?MODULE, #{
        id => Name,
        start => {hls_node, start_link, [Name, Brokers, Services, Options]},
        restart => temporary,
        type => supervisor,
        shutdown => infinity
    }).

-doc "Stops a supervised node and its connections without resetting its device.".
-spec stop_node(node()) -> ok | {error, not_found}.
stop_node(Name) -> supervisor:terminate_child(?MODULE, Name).

-doc "Defines supervision for explicitly attached nodes.".
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) -> {ok, {#{strategy => one_for_one, intensity => 3, period => 5}, []}}.
