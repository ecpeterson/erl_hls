-module(hls_domain_board_host).
-moduledoc """
Platform-only attachment for the shared Phi independent-endpoint witness.

One central BEAM owns all ordinary brokers, domain owners and paired workers.
Caller-prepared authenticated relay commands expose each board's two DMA banks
as local FIFO pairs; native crossing DATA/ACK packets stay on FPGA Ethernet.
This entry accepts only an explicitly cold, quiescent deployment. Namespace,
management session and durable incarnation stores remain deployment authorities;
none is inferred from a host PID or silently replaced after transport loss.

The attached witness uses natural output delivery. It observes actual actor
failure and replacement, without claiming a deliberately held-output frontier
or any physical fault injection. The separate transport report distinguishes
remote descriptor closure from native DMA draining/cancellation.
""".
-export([run/4, cold_status/3]).
-export_type([options/0]).

-doc "Explicit externally excluded identities and existing durable stores. create_stores=true exclusively creates a new deployment's stores and fails if either exists; false never recreates a missing store.".
-type options() :: #{namespace := hls_nums:u64(), session := hls_nums:u64(),
    first_request := hls_nums:u32(), incarnation_files := #{0 := file:filename(), 1 := file:filename()},
    create_stores := boolean()}.

-doc "Attaches four fresh FIFO brokers after transport.ready, checks matching source metadata and physical roles, establishes both parsers on each cold board, then invokes the shared application witness. No SSH command, device open, rebuild or cold reset occurs here. Failure closes the attachment through Stage/finished; there is no reconnect or replay.".
-spec run(file:filename(), file:filename(), file:filename(), options()) -> ok.
run(Bundle, Network, Stage, #{namespace := Namespace, session := Session, first_request := First,
    incarnation_files := Stores, create_stores := Create} = Options) ->
    [create_stores, first_request, incarnation_files, namespace, session] = lists:sort(maps:keys(Options)),
    true = is_integer(Namespace) andalso Namespace > 0 andalso Namespace < (1 bsl 64),
    true = is_integer(Session) andalso Session > 0 andalso Session < (1 bsl 64),
    true = is_integer(First) andalso First > 0 andalso First < (1 bsl 32),
    true = is_boolean(Create), [0, 1] = lists:sort(maps:keys(Stores)),
    {ok, DomainBytes} = file:read_file(filename:join(Bundle, "interface.etf")),
    {ok, DomainBytes} = file:read_file(filename:join([Network, "evidence", "domain-interface.etf"])),
    #{domains := DomainRows} = binary_to_term(DomainBytes),
    [0, 1] = lists:sort([I || #{index := I} <- DomainRows]),
    {ok, FixtureBytes} = file:read_file(filename:join(Bundle, "fixture.etf")),
    #{actors := Actors} = binary_to_term(FixtureBytes),
    Phases = maps:from_list([begin
        #{codecs := #{phase := Phase}} = hls_domain_wire:load(filename:join(
            [Bundle, "domain_" ++ integer_to_list(Index), "domain", "interface.etf"])),
        {Index, Phase}
    end || Index <- [0, 1]]),
    wait_ready(Stage, erlang:monotonic_time(millisecond) + 30000),
    case Create of
        true -> [ok = hls_domain_ids:create(maps:get(I, Stores)) || I <- [0, 1]];
        false -> ok
    end,
    with_roles(Stage, Stores, Phases, Session, First, fun(Roles, Clients) ->
        Inspect = fun(Index, Epoch) -> inspect(Stage, Index, Epoch, Session,
            maps:get(Index, Clients), DomainRows, Actors) end,
        phi_domain_repetition_live:run_attached(Bundle, Stage,
            #{mode => independent_endpoints, network_bundle => Network, namespace => Namespace},
            #{roles => Roles, inspect => Inspect})
    end).

-doc "Checks a cold board observation using the retained native codec for the unbound phase. Only the expected role with zero sessions/incarnation, detached parsers and no retained transport/router/carrier fault is cold. Carrier arming is checked separately before startup; this predicate is not a proof that DMA banks are drained.".
-spec cold_status(0 | 1, hls_domain_board_client:snapshot(), hls_type:descriptor()) -> boolean().
cold_status(Index, #{kind := board, abi := 1, role := Role, status := ok,
    domain_session := 0, endpoint_session := 0, incarnation := 0,
    health := #{phase_code := PhaseCode, domain_attached := false, endpoint_attached := false,
        domain_wire_fault := false, endpoint_wire_fault := false, router_fault := false, carrier_fault := 0}}, Phase)
    when Role =:= Index + 1 ->
    Width = hls_type:width(Phase),
    <<Unbound:Width>> = hls_type:pack(unbound, Phase), PhaseCode =:= Unbound;
cold_status(_, _, _) -> false.

%% A failed partial attachment retires its already opened role before propagating failure.
-spec with_roles(file:filename(), map(), map(), pos_integer(), pos_integer(), fun((map(), map()) -> ok)) -> ok.
with_roles(Stage, Stores, Phases, Session, First, Fun) ->
    with_role(Stage, 0, maps:get(0, Stores), maps:get(0, Phases), Session, First, fun(Role0, Client0) ->
        with_role(Stage, 1, maps:get(1, Stores), maps:get(1, Phases), Session, First, fun(Role1, Client1) ->
            Fun(#{0 => Role0, 1 => Role1}, #{0 => Client0, 1 => Client1})
        end)
    end).

%% One bank-one broker is shared by domain route 0, endpoint route 2 and board routes 3/4.
-spec with_role(file:filename(), 0 | 1, file:filename(), hls_type:descriptor(), pos_integer(), pos_integer(),
    fun((map(), pid()) -> ok)) -> ok.
with_role(Stage, Index, Store, Phase, Session, First, Fun) ->
    Prefix = filename:join(Stage, "board" ++ integer_to_list(Index)),
    Application = broker(Prefix ++ "_application"),
    try
        Management = broker(Prefix ++ "_management"),
        try
            {ok, Client} = hls_domain_board_client:start_link(Management,
                #{first_request => First, timeout_ms => 10000}),
            unlink(Client),
            try
                Cold = await_cold(Client, Index, Phase, erlang:monotonic_time(millisecond) + 30000),
                _ = hls_dma_device:await_broker(Application, 5000),
                _ = hls_dma_device:await_broker(Management, 5000),
                {ok, Established = #{status := ok, domain_session := Session, endpoint_session := Session}} =
                    hls_domain_board_client:establish(Client, Session),
                ok = file:write_file(filename:join(Stage, "board" ++ integer_to_list(Index) ++ "-bootstrap.etf"),
                    term_to_binary(#{cold => Cold, established => Established}), [exclusive]),
                Fun(#{application => Application, management => Management, session => Session,
                    incarnation_file => Store}, Client)
            after catch hls_domain_board_client:stop(Client) end
        after catch hls_fabric:stop(Management) end
    after
        catch hls_fabric:stop(Application), finish(Stage)
    end.

%% Native sessions remain untouched until the physical carrier has become healthy once.
-spec await_cold(pid(), 0 | 1, hls_type:descriptor(), integer()) -> hls_domain_board_client:snapshot().
await_cold(Client, Index, Phase, Deadline) ->
    {ok, Snapshot = #{health := #{carrier_armed := Armed}}} = hls_domain_board_client:status(Client),
    true = cold_status(Index, Snapshot, Phase),
    case Armed of
        true -> Snapshot;
        false -> true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 25 -> await_cold(Client, Index, Phase, Deadline) end
    end.

%% Retained global actor indices are passed unchanged to the sparse native inspector.
-spec inspect(file:filename(), non_neg_integer(), pos_integer(), pos_integer(), pid(), [map()], [map()]) -> ok.
inspect(Stage, Index, Epoch, Session, Client, Domains, Actors) ->
    [Domain] = [Id || #{index := I, id := Id} <- Domains, I =:= Index],
    Values = [begin
        {ok, Value = #{status := Status}} = hls_domain_board_client:inspect(Client, Session, Epoch, Address),
        true = Status =:= ok orelse Status =:= unsupported,
        Value
    end || #{index := Address, domain := Id} <- Actors, Id =:= Domain],
    {ok, Health = #{incarnation := Epoch, health := #{carrier_fault := 0, router_fault := false,
        domain_wire_fault := false, endpoint_wire_fault := false}}} = hls_domain_board_client:status(Client),
    file:write_file(filename:join(Stage, "board" ++ integer_to_list(Index) ++ "-inspection-" ++
        integer_to_list(Epoch) ++ ".etf"), term_to_binary(#{status => Health, values => Values}), [exclusive]).

%% Ordinary local brokers retain production framing, credit, ownership and failure semantics.
-spec broker(file:filename()) -> pid().
broker(Prefix) ->
    {ok, Broker} = hls_fabric:start_link(Prefix ++ "_tx", Prefix ++ "_rx",
        #{rx_route_limit => 1, rx_limit => 4, tx_route_limit => 4, tx_limit => 16}),
    unlink(Broker), Broker.

%% Readiness means every exact authenticated helper version/bank handshake was observed.
-spec wait_ready(file:filename(), integer()) -> ok.
wait_ready(Stage, Deadline) ->
    case file:read_file(filename:join(Stage, "transport.ready")) of
        {ok, <<"1\n">>} -> ok;
        _ -> true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 10 -> wait_ready(Stage, Deadline) end
    end.

%% Closing the host peer unblocks FIFO readers; remote native ownership is not thereby drained.
-spec finish(file:filename()) -> ok.
finish(Stage) ->
    case file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]) of
        ok -> ok;
        {error, eexist} -> ok;
        {error, Reason} -> error({transport_finish, Reason})
    end.
