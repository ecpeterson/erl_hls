-module(hls_domain_endpoints_stream_tests).
-moduledoc "Independent endpoint management wire and source-emission checks. Exact vectors cover retained binding packing and canonical responses; emitted pins and bounded parser storage are checked without XLS execution, peer coordination or physical transport claims.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Independent byte vectors retain all four 64-bit binding identities and the explicit endpoint ID.
-spec wire_vectors_test() -> ok.
wire_vectors_test() ->
    Interface = interface(),
    Binding = #endpoint_binding{namespace = 16#123456789abcdef0, generation = 16#100000002,
        source_incarnation = 16#300000004, destination_incarnation = 16#500000006},
    Prefix = <<41:64/little, 7:32/little, 8:32/little>>,
    Packed = <<16#123456789abcdef0:64/little, 16#100000002:64/little,
        16#300000004:64/little, 16#500000006:64/little>>,
    ?assertEqual({0, Prefix}, hls_domain_endpoint_wire:command(41, 7, 8, inspect, Interface)),
    ?assertEqual({1, <<Prefix/binary, Packed/binary>>},
        hls_domain_endpoint_wire:command(41, 7, 8, {bind, Binding}, Interface)),
    ?assertEqual({2, <<Prefix/binary, Packed/binary>>},
        hls_domain_endpoint_wire:command(41, 7, 8, {fence, Binding}, Interface)),
    Flags = status(accepted, Interface) bor (1 bsl 8),
    Reply = <<Prefix/binary, Flags:32/little, Packed/binary, 16#f0000001:32/little>>,
    ?assertEqual(#{session => 41, request => 7, endpoint => 8,
        snapshot => #{kind => tx, status => accepted, binding => Binding,
            packet_sequence => 16#f0000001, active => true, fault => false}},
        hls_domain_endpoint_wire:observation({129, 0, 0}, Reply, Interface)),
    ok.

%% Invalid framing, flags, enum values and active identities cannot masquerade as endpoint evidence.
-spec wire_rejection_test() -> ok.
wire_rejection_test() ->
    Interface = interface(),
    Binding = #endpoint_binding{namespace = 11, generation = 1,
        source_incarnation = 2, destination_incarnation = 3},
    Reply = reply(8, 0, Binding, Interface),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({1, 0, 0}, Reply, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 1, 0}, Reply, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 0, 1}, Reply, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 0, 0}, <<>>, Interface)),
    [begin
        Bad = reply(8, Flags, Binding, Interface),
        ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 0, 0}, Bad, Interface))
    end || Flags <- [1 bsl 10, 1 bsl 31, (1 bsl 8) bor (1 bsl 9), 7]],
    ActiveZero = reply(8, 1 bsl 8, #endpoint_binding{}, Interface),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 0, 0}, ActiveZero, Interface)),
    Unknown = reply(99, 0, Binding, Interface),
    ?assertException(error, _, hls_domain_endpoint_wire:observation({129, 0, 0}, Unknown, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:command(0, 1, 8, inspect, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:command(1, 0, 8, inspect, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:command(1, 1, 99, inspect, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:command(1, 1, 8,
        {bind, #endpoint_binding{}}, Interface)),
    ?assertException(error, _, hls_domain_endpoint_wire:command(1, 1, 8,
        {fence, Binding#endpoint_binding{namespace = 1 bsl 64}}, Interface)),
    ok.

%% Static interface mistakes reject before any generated parser or external tool exists.
-spec metadata_rejection_test() -> ok.
metadata_rejection_test() ->
    Interface = interface(),
    ?assertException(error, _, hls_domain_endpoint_wire:load(Interface#{response_tag := 1})),
    ?assertException(error, _, hls_domain_endpoint_wire:load(Interface#{management_route := {0, 65536}})),
    ?assertException(error, _, hls_domain_endpoint_wire:load(Interface#{endpoints := []})),
    ?assertException(error, _, hls_domain_endpoint_wire:load(Interface#{endpoints :=
        [#{id => 8, kind => tx}, #{id => 8, kind => rx}]})),
    ?assertException(error, _, hls_domain_endpoint_wire:load(Interface#{endpoints := [#{id => 8, kind => both}]})),
    ok.

%% One parser selects local metadata; neither lifecycle nor endpoint reset is a management output.
-spec emission_test() -> ok.
emission_test() ->
    Config = #{endpoints => [#{id => 8, kind => tx}, #{id => 61, kind => rx}], codecs => codecs()},
    #{files := Files, result := Result} = hls_domain_endpoints_stream:emit(Config),
    #{inputs := Inputs, outputs := Outputs, interface := Interface, unit := Unit} = Result,
    ?assertMatch(#{state_bit_budget := 1159, payload_words := 14, packet_words := 16}, Result),
    ?assertMatch(#{kind := domain_endpoint_management, management_route := {0, 2}, response_tag := 129}, Interface),
    ?assertEqual(Interface, hls_domain_endpoint_wire:load(Interface)),
    ?assertEqual(<<"endpoint_management_clock">>, maps:get(top, Unit)),
    ?assert(lists:member({"endpoint_8_receiver_active", 1}, Outputs)),
    ?assertNot(lists:keymember("endpoint_61_receiver_active", 1, Outputs)),
    ?assert(lists:member({"endpoint_61_observed_bound_namespace", 64}, Inputs)),
    ?assert(lists:member({"endpoint_8_namespace", 64}, Outputs)),
    ?assertEqual([], [Name || {Name, _} <- Outputs, lists:suffix("reset", Name)]),
    ?assertEqual([], [Name || {Name, _} <- Inputs, lists:suffix("local_ready", Name) orelse
        lists:suffix("local_incarnation", Name)]),
    Names = [Name || {Name, _} <- Inputs ++ Outputs],
    ?assertEqual(length(Names), length(lists:usort(Names))),
    Text = iolist_to_binary(maps:get("endpoint_management/endpoint_management.x", Files)),
    ?assertEqual(nomatch, binary:match(Text, <<"@@">>)),
    includes(Text, "const ROUTE = u32:2;"),
    includes(Text, "framing::header(packet.header, u8:129, u8:14)"),
    includes(Text, "endpoint_8_receiver_active: bind_enabled && endpoint == u32:8"),
    includes(Text, "endpoint_8_receiver_namespace: if bind_enabled && endpoint == u32:8"),
    includes(Text, "namespace: value[0+:u64]"),
    includes(Text, "destination_incarnation: value[192+:u64]"),
    includes(Text, "packet.route == ROUTE && (packet.header & u32:0x00ffff00) == u32:0"),
    includes(Text, "s.rx.seen >= u32:2 && pair(packet, u32:0) == s.session"),
    includes(Text, "_ => zero!<Observation>()"),
    includes(Text, "response(packet, observed)"),
    #{files := CustomFiles} = hls_domain_endpoints_stream:emit(Config#{management_route => {7, 9}}),
    includes(iolist_to_binary(maps:get("endpoint_management/endpoint_management.x", CustomFiles)),
        "const ROUTE = u32:458761;"),
    #{files := A, result := #{top_module := "role_a_management", core_module := "role_a_management_core", unit := UnitA}} =
        hls_domain_endpoints_stream:emit(Config#{top_module => "role_a_management"}),
    #{files := B} = hls_domain_endpoints_stream:emit(Config#{top_module => "role_b_management"}),
    ?assertEqual([], [Path || Path <- maps:keys(A), maps:is_key(Path, B)]),
    ?assertEqual(<<"role_a_management_core">>, maps:get(module, UnitA)),
    ?assertEqual(<<"endpoint_management_clock">>, maps:get(top, UnitA)),
    includes(iolist_to_binary(maps:get("role_a_management/management.sv", A)), "module role_a_management"),
    includes(iolist_to_binary(maps:get("role_a_management/management.sv", A)), "role_a_management_core"),
    ?assertException(error, _, hls_domain_endpoints_stream:emit(Config#{top_module => "../unsafe"})),
    ok.

%% Resolve the actual source declarations without compiling an actor or invoking XLS.
-spec codecs() -> hls_domain_endpoint_wire:codecs().
codecs() ->
    Source = hls_source:library_file(hls_runtime, "fabric/runtime/domain/hls_domain_channel_tx.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Inputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_input))),
    Outputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_output))),
    #{operation => maps:get(op, Inputs), status => maps:get(status, Outputs),
        binding => maps:get(binding, Inputs)}.

%% The test interface shares source codecs but independently fixes endpoint direction and route.
-spec interface() -> hls_domain_endpoint_wire:interface().
interface() -> hls_domain_endpoint_wire:load(#{kind => domain_endpoint_management,
    management_route => {0, 2}, response_tag => 129,
    endpoints => [#{id => 8, kind => tx}, #{id => 61, kind => rx}], codecs => codecs()}).

%% Response fixtures use generic record packing; the exact command vector checks its byte order independently.
-spec reply(hls_nums:u32(), hls_nums:u32(), #endpoint_binding{}, hls_domain_endpoint_wire:interface()) -> binary().
reply(Id, Flags, Binding, #{codecs := #{binding := Type}}) ->
    Packed = hls_type:pack(Binding, Type),
    <<41:64/little, 7:32/little, Id:32/little, Flags:32/little, Packed/binary, 0:32/little>>.

%% The test never assumes numeric status encodings from a second enum table.
-spec status(endpoint_status(), hls_domain_endpoint_wire:interface()) -> non_neg_integer().
status(Atom, #{codecs := #{status := Type}}) ->
    Width = hls_type:width(Type),
    <<Code:Width>> = hls_type:pack(Atom, Type),
    Code.

%% Interface-critical source checks do not claim dynamic parser or RTL equivalence.
-spec includes(binary(), iodata()) -> ok.
includes(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))),
    ok.
