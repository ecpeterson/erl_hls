-module(hls_local_dist).
-moduledoc "Distribution carrier for locally hosted FPGA nodes; other nodes use TCP.".
-export([listen/1, listen/2, accept/1, accept_connection/5, setup/5,
    close/1, select/1, address/0, is_node_name/1, setopts/2, getopts/2]).
-export([local_setup/6]).
%% The controller API and hs_data layout are qualified against OTP 28.0.2.
%% dist_util owns the real node's handshake, connection lifecycle and ticking;
%% the service adapter is also the controller, without a forwarding mailbox.
-include_lib("kernel/include/net_address.hrl").
-include_lib("kernel/include/dist.hrl").
-include_lib("kernel/include/dist_util.hrl").

-doc "Opens the host node's ordinary TCP distribution listener.".
-spec listen(atom()) -> {ok, {gen_tcp:socket(), #net_address{}, non_neg_integer()}} | {error, term()}.
listen(Name) -> inet_tcp_dist:listen(Name).
-doc "Opens the host node's TCP distribution listener for the given host.".
-spec listen(atom(), string()) -> {ok, {gen_tcp:socket(), #net_address{}, non_neg_integer()}} | {error, term()}.
listen(Name, Host) -> inet_tcp_dist:listen(Name, Host).
-doc "Starts the ordinary TCP distribution acceptor.".
-spec accept(gen_tcp:socket()) -> pid().
accept(Listen) -> inet_tcp_dist:accept(Listen).
-doc "Starts authentication of an accepted TCP distribution connection.".
-spec accept_connection(pid(), gen_tcp:socket(), node(), [node()], non_neg_integer()) -> pid().
accept_connection(Acceptor, Controller, Node, Allowed, Time) ->
    inet_tcp_dist:accept_connection(Acceptor, Controller, Node, Allowed, Time).
-doc "Closes a TCP distribution listener or connection.".
-spec close(gen_tcp:socket()) -> ok.
close(Listen) -> inet_tcp_dist:close(Listen).
-doc "Reports whether the node name is eligible for this carrier.".
-spec select(node()) -> boolean().
select(Node) -> inet_tcp_dist:select(Node).
-doc "Returns the host's TCP distribution address family.".
-spec address() -> #net_address{}.
address() -> inet_tcp_dist:address().
-doc "Checks node-name syntax using the TCP carrier's rules.".
-spec is_node_name(term()) -> boolean().
is_node_name(Node) -> inet_tcp_dist:is_node_name(Node).
-doc "Sets supported TCP distribution socket options.".
-spec setopts(gen_tcp:socket(), [gen_tcp:option()]) -> ok | {error, term()}.
setopts(Socket, Options) -> inet_tcp_dist:setopts(Socket, Options).
-doc "Reads supported TCP distribution socket options.".
-spec getopts(gen_tcp:socket(), [atom()]) -> {ok, [gen_tcp:option()]} | {error, term()}.
getopts(Socket, Options) -> inet_tcp_dist:getopts(Socket, Options).

-doc "Connects locally hosted FPGA nodes through their manager; other nodes use ordinary TCP distribution.".
-spec setup(node(), normal | hidden, node(), shortnames | longnames, non_neg_integer()) -> pid().
setup(Node, Type, MyNode, Naming, Time) ->
    case hls_node:local_manager(Node) of
        undefined -> inet_tcp_dist:setup(Node, Type, MyNode, Naming, Time);
        Manager -> spawn_opt(?MODULE, local_setup,
            [self(), Manager, Node, Type, MyNode, Time], dist_util:net_ticker_spawn_options())
    end.

-doc "Runs the local carrier handshake and distribution connection lifecycle.".
-spec local_setup(pid(), pid(), node(), normal | hidden, node(), non_neg_integer()) -> no_return().
local_setup(Kernel, Manager, Node, Type, MyNode, Time) ->
    Timer = dist_util:start_timer(Time),
    {ok, Controller} = gen_server:call(Manager, {local_connection, self()}),
    link(Controller),
    [_Name, Host] = string:split(atom_to_list(Node), "@"),
    HS = #hs_data{kernel_pid = Kernel, other_node = Node, this_node = MyNode,
        socket = Controller, timer = Timer, this_flags = 0,
        other_version = ?ERL_DIST_VER_6, request_type = Type,
        f_send = fun(C, Packet) -> gen_server:call(C, {handshake_send, Packet}) end,
        f_recv = fun(C, _Length, _Timeout) -> gen_server:call(C, handshake_recv) end,
        f_setopts_pre_nodeup = fun(_) -> ok end,
        f_setopts_post_nodeup = fun(_) -> ok end,
        f_getll = fun(C) -> {ok, C} end,
        f_address = fun(_, _) -> #net_address{host = Host, protocol = hls_local,
            family = inet, address = {local, Node}} end,
        f_handshake_complete = fun(C, _, Handle) -> gen_server:call(C, {local_up, Handle}) end,
        mf_tick = fun(C) -> gen_server:cast(C, local_tick) end,
        mf_getstat = fun(C) -> gen_server:call(C, local_stats) end,
        mf_setopts = fun(_, _) -> {error, enotsup} end,
        mf_getopts = fun(_, _) -> {error, enotsup} end},
    dist_util:handshake_we_started(HS).
