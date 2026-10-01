-module(hls_node_wire).
-moduledoc false.
-export([register/3, handshake/3, handshake_start/2, handshake_step/2, pid/3, decode/1, encode/1, encode/2, reply/3]).
-include_lib("kernel/include/dist.hrl").

%% Public node identity used throughout a connection handshake.
-type identity() :: #{name := node(), creation := non_neg_integer()}.

%% A deliberately small negotiated protocol: pass-through ETF, without atom
%% caches or fragments. ERTS chooses the mutually supported representation.
%% Negotiate pass-through ETF and monitors/aliases, without atom caches or fragmentation.
-spec flags() -> non_neg_integer().
flags() -> ?DFLAGS_MANDATORY bor ?DFLAG_MANDATORY_25_DIGEST bor
    ?DFLAG_DIST_MONITOR bor ?DFLAG_DIST_MONITOR_NAME bor ?DFLAG_SMALL_ATOM_TAGS bor
    ?DFLAG_SEND_SENDER bor ?DFLAG_ALIAS.

-doc "Registers the node with local EPMD; the returned socket must stay open for that incarnation.".
-spec register(node(), inet:port_number(), inet:port_number()) -> {gen_tcp:socket(), non_neg_integer()}.
register(Name, Port, EpmdPort) ->
    [Short, _Host] = binary:split(atom_to_binary(Name, utf8), <<"@">>),
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, EpmdPort,
        [binary, {active, false}, {packet, 2}], 5000),
    try
        ok = gen_tcp:send(Socket, <<120, Port:16, 72, 0, 6:16, 6:16,
            (byte_size(Short)):16, Short/binary, 0:16>>),
        ok = inet:setopts(Socket, [{packet, 0}]),
        {ok, <<118, 0, Creation:32>>} = gen_tcp:recv(Socket, 6, 5000),
        ok = inet:setopts(Socket, [{active, once}]),
        {Socket, Creation}
    catch Class:Reason:Stack ->
        gen_tcp:close(Socket), erlang:raise(Class, Reason, Stack)
    end.

-doc "Authenticates an incoming peer within five seconds per read, then selects four-byte packet framing. Raises on failure.".
-spec handshake(gen_tcp:socket(), identity(), atom()) -> node().
handshake(Socket, Identity, Cookie) ->
    State = handshake_start(Identity, Cookie),
    {ok, NamePacket} = gen_tcp:recv(Socket, 0, 5000),
    {ChallengePackets, ChallengeState} = handshake_step(NamePacket, State),
    [ok = gen_tcp:send(Socket, Packet) || Packet <- ChallengePackets],
    {ok, ReplyPacket} = gen_tcp:recv(Socket, 0, 5000),
    {[Ack], #{peer := Peer}} = handshake_step(ReplyPacket, ChallengeState),
    ok = gen_tcp:send(Socket, Ack),
    ok = inet:setopts(Socket, [{packet, 4}]),
    Peer.

-doc "Creates incoming handshake state containing the cookie; keep this state private.".
-spec handshake_start(identity(), atom()) -> map().
handshake_start(Identity, Cookie) -> Identity#{phase => name, cookie => Cookie}.
-doc "Consumes one handshake packet and returns replies plus the next state; rejects invalid authentication or flags.".
-spec handshake_step(binary(), map()) -> {[binary()], map()}.
handshake_step(<<$N, PeerFlags:64, _PeerCreation:32, Length:16, PeerName:Length/binary, _/binary>>,
        State = #{phase := name, name := Name, creation := Creation}) ->
    Expanded = case PeerFlags band ?DFLAG_MANDATORY_25_DIGEST of
        0 -> PeerFlags;
        _ -> PeerFlags bor ?MANDATORY_DFLAGS_25
    end,
    true = (Expanded band ?DFLAGS_MANDATORY) =:= ?DFLAGS_MANDATORY,
    Required = ?DFLAG_DIST_MONITOR bor ?DFLAG_ALIAS,
    true = (Expanded band Required) =:= Required,
    <<Challenge:32>> = crypto:strong_rand_bytes(4),
    NameBytes = atom_to_binary(Name, utf8),
    Packet = <<$N, (flags()):64, Challenge:32, Creation:32,
        (byte_size(NameBytes)):16, NameBytes/binary>>,
    {[<<"sok">>, Packet], State#{phase := reply, challenge => Challenge,
        peer_name => PeerName}};
handshake_step(<<$r, PeerChallenge:32, Received:16/binary>>,
        State = #{phase := reply, cookie := Cookie, challenge := Challenge, peer_name := PeerName}) ->
    true = Received =:= digest(Cookie, Challenge),
    %% Do not intern a peer name until its cookie has authenticated it.
    Peer = binary_to_atom(PeerName, utf8),
    {[<<$a, (digest(Cookie, PeerChallenge))/binary>>],
        (maps:without([cookie, peer_name], State))#{phase := up, peer => Peer}}.

%% Compute the distribution challenge response using the cookie's Latin-1 bytes.
-spec digest(atom(), non_neg_integer()) -> binary().
digest(Cookie, Challenge) ->
    erlang:md5([atom_to_binary(Cookie, latin1), integer_to_binary(Challenge)]).

%% External PIDs are real Erlang terms, but never name a host process. Creation
%% is obtained from EPMD once per node activation, not once per connection.
-doc "Constructs an external PID for a node incarnation; it never names a local host process.".
-spec pid(node(), non_neg_integer(), non_neg_integer()) -> pid().
pid(Name, Creation, ID) ->
    <<131, Atom/binary>> = term_to_binary(Name),
    binary_to_term(<<131, 88, Atom/binary, ID:32, 0:32, Creation:32>>).

-doc "Decodes one authenticated pass-through distribution packet, rejecting trailing payload bytes. May intern atoms.".
-spec decode(binary()) -> {tuple(), none | {message, term()}}.
decode(<<112, Terms/binary>>) ->
    {Control, Used} = binary_to_term(Terms, [used]),
    case Terms of
        <<_:Used/binary>> -> {Control, none};
        <<_:Used/binary, Payload/binary>> ->
            {Message, Size} = binary_to_term(Payload, [used]),
            true = Size =:= byte_size(Payload),
            {Control, {message, Message}}
    end.

-doc "Encodes a distribution control signal without a message payload.".
-spec encode(tuple()) -> iolist().
encode(Control) -> [112, term_to_binary(Control)].
-doc "Encodes a distribution control signal and its message payload.".
-spec encode(tuple(), term()) -> iolist().
encode(Control, Message) -> [encode(Control), term_to_binary(Message)].

-doc "Encodes a gen_server reply, addressing its alias when the caller supplied one.".
-spec reply(pid(), {pid(), term()}, term()) -> iolist().
reply(Sender, {_Caller, [alias | Alias] = Tag}, Reply) when is_reference(Alias) ->
    encode({33, Sender, Alias}, {Tag, Reply});
reply(Sender, {Caller, Tag}, Reply) -> encode({22, Sender, Caller}, {Tag, Reply}).
