-module(hls_test_nodes).
-export([distribution/0, start_peer/0, request/3]).

distribution() ->
    case node() of
        nonode@nohost ->
            _ = os:cmd("epmd -daemon"),
            Name = list_to_atom("fabric_test_" ++ integer_to_list(erlang:unique_integer([positive]))),
            {ok, _} = net_kernel:start(Name, #{name_domain => shortnames});
        _ -> ok
    end.
start_peer() ->
    Paths = [filename:absname(Path) || Path <- code:get_path()],
    {ok, Peer, Node} = peer:start_link(#{name => peer:random_name(), connection => standard_io,
        args => ["+S", "2:2", "+A", "2", "-connect_all", "false", "-pa" | Paths]}),
    {Peer, Node}.

request(Pid, Message, ReplyTo) ->
    spawn(fun() -> ReplyTo ! {remote_reply, gen_server:call(Pid, Message, infinity)} end).
