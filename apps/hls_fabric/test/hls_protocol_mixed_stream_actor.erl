-module(hls_protocol_mixed_stream_actor).
-moduledoc "Two finite BEAM mailbox modes for mixed-owner tests. The existing network fixture supplies the total record codec; no compiler or hardware is modeled here.".
-behaviour(hls_statem).
-export([init/1, waiting/3, running/3, connect/2, pack/1, unpack/2, pack_tag/1, pack_width/1]).

-doc "Starts disconnected with an empty consumption log; the test chooses whether totals are consumed or postponed.".
-spec init(waiting | running) -> {ok, waiting | running, [non_neg_integer()]}.
init(Mode) -> {ok, Mode, []}.

-doc "Retains every total in the actual bounded hls_statem mailbox without consuming it.".
-spec waiting(enter, atom(), [non_neg_integer()]) -> {[non_neg_integer()], []};
    (cast, {total, non_neg_integer()}, [non_neg_integer()]) -> {waiting, [non_neg_integer()], postpone}.
waiting(enter, _, Data) -> {Data, []};
waiting(cast, {total, _}, Data) -> {waiting, Data, postpone}.

-doc "Consumes totals and records their values newest first, without publishing messages.".
-spec running(enter, atom(), [non_neg_integer()]) -> {[non_neg_integer()], []};
    (cast, {total, non_neg_integer()}, [non_neg_integer()]) -> {running, [non_neg_integer()], consume}.
running(enter, _, Data) -> {Data, []};
running(cast, {total, Value}, Data) -> {running, [Value | Data], consume}.

-doc "Connects through the public runtime API; the mixed owner remains the sole input writer.".
-spec connect(pid(), map()) -> ok.
connect(Pid, Outputs) -> hls_statem:connect(Pid, Outputs).

-doc "Uses the existing fixture's canonical total encoding.".
-spec pack({total, non_neg_integer()}) -> bitstring().
pack(Message) -> hls_protocol_network_fixture:pack(Message).

-doc "Decodes the same existing total schema and returns its remaining stream bits.".
-spec unpack(total, bitstring()) -> {{total, non_neg_integer()}, bitstring()}.
unpack(total, Bits) -> hls_protocol_network_fixture:unpack(total, Bits).

-doc "Returns the existing total operation selector.".
-spec pack_tag(total) -> byte().
pack_tag(total) -> hls_protocol_network_fixture:pack_tag(total).

-doc "Returns the existing total payload width.".
-spec pack_width(total) -> non_neg_integer().
pack_width(total) -> hls_protocol_network_fixture:pack_width(total).
