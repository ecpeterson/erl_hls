-module(hls_cross_domain_build).
-moduledoc "Builds the finite A-to-B retirement fixture and exports public-pin stimulus metadata. Native observations supply expected source reports; compiler-owned codecs and rectangle bindings supply every numeric frame.".

%% External fixture generation; running XLS or RTL remains the driver boundary.
-export([write/2]).

-doc "Writes a fresh three-domain bundle and fixture.json using NativeStage/native-history.etf. Requires compiled fixture modules and a successful native witness. Returns the JSON-ready metadata; does not invoke external tools.".
-spec write(file:filename(), file:filename()) -> map().
write(Bundle, NativeStage) ->
    {ok, NativeBytes} = file:read_file(filename:join(NativeStage, "native-history.etf")),
    #{passed := true, history := History} = binary_to_term(NativeBytes, [safe]),
    Config = #{sources => [{"test/hls_cross_domain_producer.erl", []},
        {"test/hls_cross_domain_consumer.erl", []}, {"test/hls_domain_counter.erl", []}],
        topology => {hls_cross_domain_producer, topology, []}, actor_limit => 3,
        control => rectangle, activation => automatic, frame_payload_words => 20},
    Placement = #{domains => [{a, [0]}, {b, [1]}, {c, [2]}], restart_groups => [[a, b], [c]]},
    _ = hls_protocol_domains:write(Config, Placement, Bundle),
    {ok, InterfaceBytes} = file:read_file(filename:join(Bundle, "interface.etf")),
    Interface = #{domains := Domains, crossings := [Crossing], channel := Channel,
        frame_payload_words := Words, codecs := DomainCodecs} = binary_to_term(InterfaceBytes, [safe]),
    Layout = hls_frame_layout:new(Words),
    Actors = actors(Layout),
    DomainMetadata = maps:from_list([{maps:get(id, D), domain(D)} || D <- Domains]),
    Stimuli = maps:from_list([begin
        Domain = find_domain(Id, Domains),
        {Name, stimulus(Id, Message, Domain, Actors, Layout)}
    end || {Name, Id, Message} <- commands()]),
    #{index := Link, source_domain := Source, destination_domain := Destination,
        link := #{slots := Slots, classes := Classes}} = Crossing,
    ChannelMetadata = #{index => Link, prefix => b("ch_" ++ integer_to_list(Link) ++ "_"),
        source_domain => Source, destination_domain => Destination, slots => Slots,
        storage_bits => maps:get(storage_bits, Channel),
        classes => [#{slot => Slot} || #{slot := Slot} <- Classes],
        inputs => ports(maps:get(inputs, Channel)), outputs => ports(maps:get(outputs, Channel)),
        codecs => codecs(maps:get(codecs, Channel))},
    Metadata = #{version => 1, top => protocol_domains,
        frame_payload_words => Words, frame_bits => hls_frame_layout:frame_bits(Layout),
        inputs => ports(maps:get(inputs, Interface)), outputs => ports(maps:get(outputs, Interface)),
        domains => DomainMetadata, channel => ChannelMetadata,
        domain_codecs => codecs(DomainCodecs), channel_codecs => codecs(maps:get(codecs, Channel)),
        stimuli => Stimuli, expected => expected(History, Actors, Layout),
        restart_groups => [[a, b], [c]],
        native_history_file => b(filename:absname(filename:join(NativeStage, "native-history.etf")))},
    ok = file:write_file(filename:join(Bundle, "fixture.json"), json:encode(Metadata), [exclusive]),
    Metadata.

%% The three static role identities agree with the shared topology, not HDL port order.
-spec actors(hls_frame_layout:layout()) -> map().
actors(Layout) ->
    Definitions = [{a, 0, hls_cross_domain_producer, producer, {0, 0}},
        {b, 1, hls_cross_domain_consumer, consumer, {1, 0}},
        {c, 2, hls_domain_counter, counter, {2, 0}}],
    Interfaces = hls_actor_interface:from_modules([M || {_, _, M, _, _} <- Definitions], Layout),
    maps:from_list([{Id, #{id => Id, index => Index, module => Module, device => Id,
        target => Target, point => Point,
        schemas => hls_host_codec_plan:schemas(maps:get(Module, Interfaces))}}
        || {Id, Index, Module, Target, Point} <- Definitions]).

%% Expected reports are the public native values; extra held traffic has no expected new-incarnation output.
-spec commands() -> [{atom(), a | b | c, tuple()}].
commands() ->
    [{initial_a, a, {read, 1, 0}}, {initial_b, b, {read, 2, 0}}, {initial_c, c, {add, 3, 7}},
     {before_burst, a, {burst, 10, 3}}, {before_a, a, {read, 12, 0}},
     {before_b, b, {read, 13, 0}}, {before_c, c, {read, 14, 0}},
     {held_burst, a, {burst, 90, 99}}, {explode_b, b, {explode, 20, 0}},
     {after_a, a, {read, 30, 0}}, {after_b, b, {read, 31, 0}}, {after_c, c, {read, 32, 0}},
     {after_burst, a, {burst, 40, 5}}, {c_add, c, {add, 50, 2}}, {c_read, c, {read, 51, 0}},
     {final_a, a, {read, 52, 0}}, {final_b, b, {read, 53, 0}}].

%% Public external stream names come from each emitted native network boundary descriptor.
-spec domain(hls_protocol_domains:domain()) -> map().
domain(#{id := Id, index := Index, actors := [Actor],
    interface := #{inputs := Inputs, outputs := Outputs,
        network := #{ingress := #{input_bits := Bits}, boundaries := Boundaries}}}) ->
    [#{source_index := Actor, name := Boundary, external_index := External}] = Boundaries,
    Prefix = "domain_" ++ integer_to_list(Index) ++ "_",
    Base = binary_to_list(Boundary),
    Ready = Base ++ "_ready",
    Valid = "app_" ++ Base ++ "_valid",
    Data = "app_" ++ Base ++ "_data",
    {Ready, 1} = lists:keyfind(Ready, 1, Inputs),
    {Valid, 1} = lists:keyfind(Valid, 1, Outputs),
    {Data, _} = lists:keyfind(Data, 1, Outputs),
    #{id => Id, index => Index, actor_index => Actor, prefix => b(Prefix), ingress_bits => Bits,
        inputs => ports(Inputs), outputs => ports(Outputs),
        report => #{ready => b(Prefix ++ Ready), valid => b(Prefix ++ Valid),
            data => b(Prefix ++ Data), external_index => External}}.

%% Per-domain projected ingress retains global target selectors and exact rectangle bounds.
-spec stimulus(a | b | c, tuple(), hls_protocol_domains:domain(), map(), hls_frame_layout:layout()) -> map().
stimulus(Id, Message, #{index := DomainIndex, interface := #{network := #{ingress := Control}}}, Actors, Layout) ->
    #{target := Target, point := {X, Y}, index := ActorIndex} = maps:get(Id, Actors),
    Ingresses = hls_protocol_control:host_ingresses(Control, maps:values(Actors)),
    #{packet := Packet, recipients := [#{index := ActorIndex}]} =
        hls_partition_ingress:select(#{frame_layout => Layout, ingresses => Ingresses},
            commands, Target, {X, Y, X, Y}, Message),
    Width = bit_size(Packet),
    <<Spatial:Width>> = Packet,
    #{actor => Id, actor_index => ActorIndex, domain_index => DomainIndex,
        message => tuple_to_list(Message), spatial => Spatial, bits => Width}.

%% Preserve the native grouping so the RTL driver can compare named before/after observations.
-spec expected(map(), map(), hls_frame_layout:layout()) -> map().
expected(History, Actors, Layout) ->
    maps:map(fun
        (_, Group) when is_map(Group) ->
            maps:map(fun(Id, Message) -> report(Id, Message, Actors, Layout) end, Group);
        (_, Reports) when is_list(Reports) ->
            [report(report_actor(Message, Actors), Message, Actors, Layout) || Message <- Reports]
    end, History).

%% Each fixture report tag belongs to exactly one actor's schema catalog.
-spec report_actor(tuple(), map()) -> atom().
report_actor(Message, Actors) ->
    Tag = element(1, Message),
    [Id] = [Id || {Id, #{schemas := Schemas}} <- maps:to_list(Actors), maps:is_key(Tag, Schemas)],
    Id.

%% Ordinary frame packing uses retained record providers and the same selected frame capacity.
-spec report(atom(), tuple(), map(), hls_frame_layout:layout()) -> map().
report(Id, Message, Actors, Layout) ->
    #{schemas := Schemas} = maps:get(Id, Actors),
    #{selector := Selector, codec := Codec} = maps:get(element(1, Message), Schemas),
    Stream = hls_record_codec:pack(Codec, Message),
    #{actor => Id, message => tuple_to_list(Message),
        frame => hls_frame_layout:pack_integer(Layout, Selector, Stream)}.

%% A fixture domain name selects its emitted instance, never an assumed module filename.
-spec find_domain(atom(), [hls_protocol_domains:domain()]) -> hls_protocol_domains:domain().
find_domain(Id, Domains) ->
    [Domain] = [D || D = #{id := Name} <- Domains, Name =:= Id],
    Domain.

%% Enum encoding is the public type provider's representation, not a duplicate constant table.
-spec codecs(#{atom() => hls_type:descriptor()}) -> map().
codecs(Codecs) ->
    maps:map(fun(_, Descriptor = {hls_type, hls_enum, enum, [Members]}) ->
        Width = hls_type:width(Descriptor),
        Values = maps:from_list([begin
            <<Value:Width>> = hls_type:pack(Member, Descriptor),
            {Member, Value}
        end || Member <- Members]),
        #{width => Width, values => Values}
    end, Codecs).

%% JSON names are strings; widths retain exact numeric sampled-port sizes.
-spec ports([{string(), pos_integer()}]) -> [map()].
ports(Ports) -> [#{name => b(Name), width => Width} || {Name, Width} <- Ports].

%% All generated paths and field names use UTF-8 JSON strings.
-spec b(string()) -> binary().
b(Text) -> unicode:characters_to_binary(Text).
