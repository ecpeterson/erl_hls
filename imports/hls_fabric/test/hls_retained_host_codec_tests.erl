-module(hls_retained_host_codec_tests).
-moduledoc "Retained production host bindings survive same-module schema reloads and actor unloading.".
-include_lib("eunit/include/eunit.hrl").
-define(ACTOR, hls_retained_host_codec_actor).
-define(PROVIDER, hls_retained_host_codec_provider).

%% A separate module and fresh sources leave every ordinary test fixture untouched.
-spec reload_and_unload_test_() -> term().
reload_and_unload_test_() -> {timeout, 120, fun reload_and_unload/0}.

%% The scheduler/partition wire supports nested padding beyond the protocol hardware subset.
-spec nested_padding_test_() -> term().
nested_padding_test_() -> {timeout, 120, fun nested_padding/0}.

%% Compatible provider implementation changes are not a new declared type or hardware build.
-spec compatible_provider_test_() -> term().
compatible_provider_test_() -> {timeout, 120, fun compatible_provider/0}.

%% Compile one unchanged provider source in two equivalent ways; only its loaded implementation changes.
-spec compatible_provider() -> ok.
compatible_provider() ->
    Root = filename:join("_build", "retained-host-provider-" ++ integer_to_list(erlang:unique_integer([positive]))),
    Source = filename:join(Root, atom_to_list(?ACTOR) ++ ".erl"),
    ProviderSource = filename:join(Root, atom_to_list(?PROVIDER) ++ ".erl"),
    false = code:is_loaded(?ACTOR), false = code:is_loaded(?PROVIDER),
    try
        ok = source(Source, custom),
        {ok, ProviderBytes} = file:read_file("test/hls_retained_host_codec_provider.erl.in"),
        ok = file:write_file(ProviderSource, ProviderBytes, [exclusive]),
        FirstCode = load_provider(ProviderSource, false),
        Config = application_config(Source),
        FirstPlan = hls_protocol_application:plan(Config),
        #{files := FirstFiles, result := FirstApplication} = hls_protocol_application:emit(FirstPlan),
        First = (host_bindings())#{application => FirstApplication},
        Expected = verify(First, 3, packed(a)),
        SecondCode = load_provider(ProviderSource, true),
        ?assertNotEqual(FirstCode, SecondCode),
        ?assertEqual({ok, ProviderBytes}, file:read_file(ProviderSource)),
        ?assertEqual(Expected, verify(First, 3, packed(a))),
        #{files := RetainedFiles, result := RetainedApplication} = hls_protocol_application:emit(FirstPlan),
        SecondPlan = hls_protocol_application:plan(Config),
        #{files := SecondFiles, result := SecondApplication} = hls_protocol_application:emit(SecondPlan),
        Second = (host_bindings())#{application => SecondApplication},
        ?assertEqual(First, Second),
        ?assertEqual(maps:with([partition, devices], FirstApplication),
            maps:with([partition, devices], RetainedApplication)),
        ?assertEqual(hardware_files(FirstFiles), hardware_files(RetainedFiles)),
        ?assertEqual(hardware_files(FirstFiles), hardware_files(SecondFiles)),
        ?assertEqual(Expected, verify(Second, 3, packed(a))),
        ok = unload(), ok = file:delete(Source),
        ?assertEqual(Expected, verify(First, 3, packed(a))),
        ?assertEqual(Expected, verify(Second, 3, packed(a))),
        ?assertEqual(false, code:is_loaded(?ACTOR)),
        ok
    after
        ok = unload(),
        _ = code:purge(?PROVIDER), _ = code:delete(?PROVIDER), _ = code:purge(?PROVIDER),
        _ = file:delete(Source), _ = file:delete(ProviderSource), _ = file:del_dir(Root)
    end.

%% The digest is a test witness that code changed; it never enters the retained schema or attachment.
-spec load_provider(file:filename(), boolean()) -> binary().
load_provider(Source, Alternate) ->
    Defines = case Alternate of false -> []; true -> [{d, 'ALTERNATE_IMPLEMENTATION'}] end,
    {ok, ?PROVIDER, Beam, []} = compile:file(Source,
        [binary, debug_info, deterministic, return_errors, return_warnings | Defines]),
    {module, ?PROVIDER} = code:load_binary(?PROVIDER, Source, Beam),
    ?PROVIDER:module_info(md5).

%% Compare executable generated inputs, excluding report and source-provenance serialization.
-spec hardware_files(hls_generated_files:files()) -> #{string() => binary()}.
hardware_files(Files) ->
    maps:from_list([{File, iolist_to_binary(Bytes)} || {File, Bytes} <- maps:to_list(Files),
        lists:member(filename:extension(File), [".x", ".sv"])]).

%% Retained host codecs preserve padding inside collection elements without widening hardware support.
-spec nested_padding() -> ok.
nested_padding() ->
    Root = filename:join("_build", "retained-host-padding-" ++ integer_to_list(erlang:unique_integer([positive]))),
    Source = filename:join(Root, atom_to_list(?ACTOR) ++ ".erl"),
    false = code:is_loaded(?ACTOR),
    try
        ok = source(Source, padded),
        {ok, ?ACTOR, Beam, []} = compile:file(Source,
            [binary, debug_info, deterministic, return_errors, return_warnings]),
        {module, ?ACTOR} = code:load_binary(?ACTOR, Source, Beam),
        Host = host_bindings(),
        Message = {work, 16#12, 16#34, [{entry, 5, -7}, {entry, 2, 3}]},
        Packed = <<16#12:8, 16#34:16/little, 2:3/little, 0:5, 3:5/little-signed,
            5:3/little, 0:5, -7:5/little-signed>>,
        ?assertEqual(Packed, ?ACTOR:pack(Message)),
        Before = verify(Host, 3, Packed, Message, [27, 40, 63]),
        ok = unload(), ok = file:delete(Source),
        ?assertEqual(Before, verify(Host, 3, Packed, Message, [27, 40, 63])),
        ?assertEqual(false, code:is_loaded(?ACTOR)),
        ok
    after
        ok = unload(), _ = file:delete(Source), _ = file:del_dir(Root)
    end.

%% Equal widths cannot make a newly loaded record order or selector authoritative for an old build.
-spec reload_and_unload() -> ok.
reload_and_unload() ->
    Root = filename:join("_build", "retained-host-codecs-" ++ integer_to_list(erlang:unique_integer([positive]))),
    FirstSource = filename:join([Root, "a", atom_to_list(?ACTOR) ++ ".erl"]),
    SecondSource = filename:join([Root, "b", atom_to_list(?ACTOR) ++ ".erl"]),
    false = code:is_loaded(?ACTOR),
    try
        ok = source(FirstSource, a),
        First = bindings(FirstSource),
        ok = malformed_bindings_are_rejected(maps:get(deployment, First)),
        PackedA = packed(a),
        ?assertEqual(50, ?ACTOR:pack_width(work)),
        ?assertEqual(PackedA, ?ACTOR:pack(message())),
        Before = verify(First, 3, PackedA),
        ok = source(SecondSource, b),
        Second = bindings(SecondSource),
        PackedB = packed(b),
        ?assertEqual(50, ?ACTOR:pack_width(work)),
        ?assertEqual(PackedB, ?ACTOR:pack(message())),
        ?assertNotEqual(PackedA, PackedB),
        ?assertEqual(Before, verify(First, 3, PackedA)),
        After = verify(Second, 4, PackedB),
        ?assertNotEqual(Before, After),
        ok = unload(),
        ok = file:delete(FirstSource),
        ok = file:delete(SecondSource),
        ?assertEqual(false, code:is_loaded(?ACTOR)),
        ?assertEqual(Before, verify(First, 3, PackedA)),
        ?assertEqual(After, verify(Second, 4, PackedB)),
        ?assertEqual(false, code:is_loaded(?ACTOR)),
        ok
    after
        ok = unload(),
        _ = file:delete(FirstSource), _ = file:delete(SecondSource),
        _ = file:del_dir(filename:dirname(FirstSource)),
        _ = file:del_dir(filename:dirname(SecondSource)),
        _ = file:del_dir(Root)
    end.

%% Construct all bindings through public APIs while this source version is loaded.
-spec bindings(file:filename()) -> map().
bindings(Source) ->
    ApplicationPlan = hls_protocol_application:plan(application_config(Source)),
    Application = hls_protocol_application:descriptor(ApplicationPlan),
    (host_bindings())#{application => Application}.

%% The custom provider stays loaded independently; only the unchanged actor source is compiled here.
-spec application_config(file:filename()) -> hls_source_config:application().
application_config(Source) ->
    #{sources => [{Source, []}], topology => {?ACTOR, topology, []},
        actor_limit => 2, device => board, host => 19}.

%% Normalize the loaded actor into both supported host-only placement paths.
-spec host_bindings() -> map().
host_bindings() ->
    Topology = hls_topology:normalize(?ACTOR:topology()),
    Groups = #{workers => #{members => [{actor, left}, {actor, right}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    Scheduler = hls_node_topology:normalize(Topology, Groups, #{workers => 7}),
    Partition = hls_partition:normalize(Topology,
        #{{actor, left} => left, {actor, right} => right}),
    Deployment = hls_partition_binding:deployment(Partition),
    #{scheduler => Scheduler, partition => Partition, deployment => Deployment}.

%% Missing retained metadata must fail validation before any session can be opened.
-spec malformed_bindings_are_rejected(map()) -> ok.
malformed_bindings_are_rejected(Deployment = #{devices := Devices, partition := Partition}) ->
    [{Device, Binding = #{events := Events}} | _] = lists:sort(maps:to_list(Devices)),
    [{Endpoint, Event = #{schemas := Schemas}} | _] = maps:to_list(Events),
    [{Tag, Schema} | _] = maps:to_list(Schemas),
    BadEvent = Event#{schemas := Schemas#{Tag := maps:remove(codec, Schema)}},
    BadBinding = Binding#{events := Events#{Endpoint := BadEvent}},
    ?assertException(error, _, hls_partition_wire:check(
        Deployment#{devices := Devices#{Device := BadBinding}})),
    #{ingresses := [Ingress = #{bindings := [Actor | Actors]} | Ingresses]} = Partition,
    BadIngress = Ingress#{bindings := [maps:remove(schemas, Actor) | Actors]},
    ?assertException(error, _, hls_partition_wire:check(
        Deployment#{partition := Partition#{ingresses := [BadIngress | Ingresses]}})),
    ok.

%% The full application uses supported narrow signed and unsigned scalar fields.
-spec message() -> tuple().
message() -> {work, 16#12, 16#34, -1234}.

%% An independent wire oracle states field order, signed narrow values and every padding bit.
-spec packed(a | b) -> bitstring().
packed(Version) ->
    Prefix = case Version of
        a -> <<16#12:8, 16#34:16/little>>;
        b -> <<16#12:16/little, 16#34:8>>
    end,
    <<Prefix/binary, -1234:26/little-signed>>.

%% Exercise the retained values, never rebuilding or calling the actor module here.
-spec verify(map(), byte(), bitstring()) -> map().
verify(Bindings, Tag, Packed) -> verify(Bindings, Tag, Packed, message(), [63]).

%% The common host checks also cover layouts outside the protocol hardware's supported subset.
-spec verify(map(), byte(), bitstring(), tuple(), [non_neg_integer()]) -> map().
verify(Bindings = #{scheduler := Scheduler = #{actors := Actors}, partition := Partition,
        deployment := Deployment}, Tag, Packed, Message, Padding) ->
    Payload = hls_codec:align(Packed, 32),
    ?assertEqual(ok, hls_node_topology:validate(Scheduler)),
    ?assertEqual(ok, hls_partition_wire:check(Deployment)),
    Casts = [begin
        Expected = {{Tag, 255, 1}, <<Slot:32/little, Payload/binary>>},
        ?assertEqual(Expected, hls_node_topology:encode_cast(Actor, Message)),
        ?assertError({invalid_request, cast, unused}, hls_node_topology:encode_cast(Actor, {unused, 1})),
        Expected
    end || Actor = #{slot := Slot} <- Actors],
    Bounds = {0, 0, 2, 0}, Command = {host, cells, Bounds, Message},
    <<Numeric:64/little>> = Payload,
    Packet = <<0:16, 0:16, 2:16, 0:16, 0:2, 2:8, 0:16, Tag:8, Numeric:96>>,
    ?assertEqual([{left, Packet}, {right, Packet}],
        hls_partition_ingress:commands(Partition, host, cells, Bounds, Message)),
    ?assertEqual([], hls_partition_ingress:commands(Partition, host, cells, {1, 0, 1, 0}, Message)),
    ?assertMatch([{left, _}], hls_partition_ingress:commands(Partition, host, cells, {0, 0, 0, 0}, Message)),
    ?assertMatch([{right, _}], hls_partition_ingress:commands(Partition, host, cells, {2, 0, 2, 0}, Message)),
    ?assertException(error, _, hls_partition_ingress:commands(Partition, host, cells, Bounds, {unused, 1})),
    Control = <<0:16/little, 0:16/little, 2:16/little, 0:16/little,
        0:32/little, 2:8, 0:16, Tag:8, Payload/binary>>,
    PartitionCommands = hls_partition_wire:command(Deployment, Command),
    ?assertEqual([{left, {1, 7}, {2, 0, 0}, Control}, {right, {2, 7}, {2, 0, 0}, Control}], PartitionCommands),
    Frame = hls_frame_layout:pack_integer(hls_frame_layout:default(), Tag, Packed),
    lists:foreach(fun(Binding) -> event_checks(Binding, Tag, Payload, Message, Padding) end,
        maps:values(maps:get(devices, Deployment))),
    case maps:find(application, Bindings) of
        error -> ok;
        {ok, Application} ->
            ?assertEqual(ok, hls_partition_wire:check(Application)),
            ?assertEqual([{board, {19, 7}, {2, 0, 0}, Control}], hls_partition_wire:command(Application, Command)),
            ?assertEqual(Control, hls_protocol_application_codec:control(Application, Command)),
            ?assertEqual({Control, [0, 1], Message}, hls_protocol_application_codec:delivery(Application, Command)),
            ?assertException(error, _, hls_protocol_application_codec:control(Application,
                {host, cells, {1, 0, 1, 0}, Message})),
            lists:foreach(fun(Binding) -> event_checks(Binding, Tag, Payload, Message, Padding) end,
                maps:values(maps:get(devices, Application))),
            ?assertEqual({reports, Message}, hls_protocol_application_codec:event(Application, board, 0, Frame))
    end,
    #{casts => Casts, partition => PartitionCommands, control => Control, frame => Frame}.

%% Both fixed-word padding and padding nested inside provider values are canonical-only.
-spec event_checks(map(), byte(), binary(), tuple(), [non_neg_integer()]) -> ok.
event_checks(Binding = #{host := Host, events := Events}, Tag, Payload, Message, Padding) ->
    [{Endpoint, _}] = maps:to_list(Events),
    Route = {Endpoint, Host}, Header = {Tag, 0, 0},
    ?assertEqual({reports, Message}, hls_partition_wire:event(Binding, Route, Header, Payload)),
    ?assertException(error, _, hls_partition_wire:event(Binding, Route, {(Tag bxor 1), 0, 0}, Payload)),
    ?assertException(error, _, hls_partition_wire:event(Binding, Route, Header, <<Payload/binary, 0:32>>)),
    lists:foreach(fun(Bit) ->
        ?assertException(error, _, hls_partition_wire:event(Binding, Route, Header, toggle(Payload, Bit)))
    end, Padding),
    ok.

%% Toggle a known zero position measured from the physical stream's first bit.
-spec toggle(binary(), non_neg_integer()) -> binary().
toggle(Payload, Position) ->
    <<Before:Position/bitstring, Bit:1, After/bitstring>> = Payload,
    <<Before/bitstring, (Bit bxor 1):1, After/bitstring>>.

%% Render only the intentional source differences; the ordinary compiler loads each version.
-spec source(file:filename(), a | b | padded | custom) -> ok.
source(Path, Version) ->
    {ok, Template} = file:read_file("test/hls_retained_host_codec_actor.erl.in"),
    {Fields, Tags} = case Version of
        First when First =:= a; First =:= padded -> {"left = hls_type:zero() :: hls_nums:u8(), right = hls_type:zero() :: hls_nums:u16()", "[work, unused]"};
        b -> {"right = hls_type:zero() :: hls_nums:u16(), left = hls_type:zero() :: hls_nums:u8()", "[unused, work]"};
        custom -> {"left = hls_type:zero() :: hls_retained_host_codec_provider:value(), "
            "right = hls_type:zero() :: hls_nums:u16()", "[work, unused]"}
    end,
    {Entry, Entries} = case Version of
        padded -> {"%% Each nested entry retains both explicit and narrow-field padding.\n"
            "-record(entry, {small = hls_type:zero() :: hls_bits:padded(hls_nums:uN(3), 8), "
            "signed = hls_type:zero() :: hls_nums:sN(5)}).", "hls_lists:list(#entry{}, 2)"};
        _ -> {"", "hls_nums:sN(26)"}
    end,
    Body = lists:foldl(fun({Pattern, Value}, Acc) ->
        binary:replace(Acc, Pattern, list_to_binary(Value))
    end, Template, [{<<"@@FIELDS@@">>, Fields}, {<<"@@TAGS@@">>, Tags},
        {<<"@@ENTRY_RECORD@@">>, Entry}, {<<"@@ENTRIES@@">>, Entries}]),
    ok = filelib:ensure_dir(Path),
    file:write_file(Path, Body, [exclusive]).

%% Remove both code generations; retained built-in provider codecs must not reload this actor.
-spec unload() -> ok.
unload() ->
    _ = code:purge(?ACTOR), _ = code:delete(?ACTOR), _ = code:purge(?ACTOR), ok.
