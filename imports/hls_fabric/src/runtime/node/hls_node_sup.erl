-module(hls_node_sup).
-moduledoc """
hls_node:start_link/4 constructs one incarnation with a manager, acceptor and connection supervisor. Significant child exit retires that incarnation rather than reconnecting hardware.
""".
-behaviour(supervisor).
%% Node-tree lifecycle and child lookup.
-export([start_link/4, child/2]).
%% Supervisor callbacks.
-export([init/1]).

-doc "Starts one node incarnation and its connection supervisors.".
-spec start_link(node(), hls_node:brokers(), [hls_node:service()], hls_node:options()) ->
    supervisor:startlink_ret().
start_link(Name, Brokers, Services, Options) ->
    supervisor:start_link(?MODULE, {Name, Brokers, Services, Options}).

-doc "Returns a live named child; fails if that child is absent.".
-spec child(pid(), node | connections | acceptor) -> pid().
child(Sup, ID) ->
    {ID, Pid, _, _} = lists:keyfind(ID, 1, supervisor:which_children(Sup)),
    Pid.

-doc "Stops the whole node incarnation when any significant child exits.".
-spec init({node(), hls_node:brokers(), [hls_node:service()], hls_node:options()}) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Name, Brokers, Services, Options}) ->
    %% No child may restart behind a live node incarnation. A new incarnation
    %% obtains a new creation and fresh return routes; hardware is not reset.
    {ok,
        {#{strategy => one_for_one, auto_shutdown => any_significant}, [
            #{
                id => connections,
                start => {hls_node_connections, start_link, []},
                type => supervisor,
                shutdown => infinity,
                restart => temporary,
                significant => true
            },
            #{
                id => node,
                start => {hls_node, start_manager, [Name, Brokers, Services, Options, self()]},
                restart => temporary,
                significant => true
            },
            #{
                id => acceptor,
                start => {hls_node_acceptor, start_link, [self()]},
                restart => temporary,
                significant => true
            }
        ]}}.
