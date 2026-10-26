-module(hls_protocol_application_binding).
-moduledoc "Source-checked host codecs shared by single-device gateways and framed deployments. Descriptors are trusted local compiler outputs, never network terms.".
-export([bind/4, control/2, delivery/2, event/4]).
-export_type([application/0, application/1, partition/0, actor/0, binding/0,
    gateway/0, attached_gateway/0, event/0]).

-doc "One globally indexed actor and its checked device owner, retaining the source module's output and mailbox declarations.".
-type actor() :: #{id := hls_protocol_topology:id(), module := module(), outputs := [atom()],
    mailbox_capacity := pos_integer(), identity := {actor, hls_protocol_topology:id()},
    index := non_neg_integer(), device := hls_source_config:device()}.

%% Each ingress binding adds a two-dimensional point and its accepted target identifiers.
-type recipient() :: #{id := hls_protocol_topology:id(), module := module(), outputs := [atom()],
    mailbox_capacity := pos_integer(), identity := {actor, hls_protocol_topology:id()},
    index := non_neg_integer(), device := hls_source_config:device(),
    point := [non_neg_integer()], targets := [hls_protocol_topology:id()]}.
%% Wire selection indexes targets independently of actor and transport endpoint identities.
-type target() :: #{id := hls_protocol_topology:id(), selector := non_neg_integer(), schemas := [atom()]}.
%% A rectangle's checked source recipients retain global coordinates through native placement.
-type ingress() :: #{frame_layout := hls_frame_layout:layout(), id := hls_protocol_topology:id(), shape := [pos_integer()],
    targets := [target()], bindings := [recipient()]}.
%% Source ports use the shared partition actor identity while logical recipient IDs stay unchanged.
-type route() :: #{source := {{actor, hls_protocol_topology:id()}, atom()},
    recipients := [hls_protocol_topology:destination()],
    delivery := direct | coupled | buffered | queued | best_effort}.

-doc "The checked host view of source actors, routes and rectangle ingress. It contains no sessions, queues or emitted hardware identities.".
-type partition() :: #{frame_layout := hls_frame_layout:layout(), actors := [actor()], routes := [route()], ingresses := [ingress()]}.

%% This is the compiler interface field shape emitted by xls_statem_lower:record_fields/1.
-type schema_field() :: #{name := atom(), type := hls_type:descriptor()}.
%% Runtime decoding uses the loaded module's exact record tag and packed width.
-type event_schema() :: #{module := module(), name := atom(), width := non_neg_integer(), fields := [schema_field()]}.

-doc "One external stream and its unambiguous ordinary-message selectors, checked against all local producer codecs.".
-type event() :: #{id := hls_protocol_topology:id(), port := string(), schemas := #{byte() => event_schema()}}.

-doc "Static source-checked host endpoints and event codecs for one device, before a gateway adapter or attachment identity is added.".
-type binding() :: #{host := hls_source_config:endpoint(), control := hls_source_config:endpoint(),
    ingress := hls_protocol_topology:id(), events := #{hls_source_config:endpoint() => event()},
    frame_layout := hls_frame_layout:layout(), activation := explicit_start}.

-doc "A whole-application host binding with its checked framed control adapter; emitted attachment identity is still absent.".
-type gateway() :: #{host := hls_source_config:endpoint(), control := hls_source_config:endpoint(),
    ingress := hls_protocol_topology:id(), events := #{hls_source_config:endpoint() => event()},
    frame_layout := hls_frame_layout:layout(), activation := explicit_start, control_adapter := hls_protocol_control:hardware()}.

-doc "The emitted whole-application binding, with the exact hardware attachment identity required by the stream client.".
-type attached_gateway() :: #{host := hls_source_config:endpoint(), control := hls_source_config:endpoint(),
    ingress := hls_protocol_topology:id(), events := #{hls_source_config:endpoint() => event()},
    frame_layout := hls_frame_layout:layout(), activation := explicit_start, control_adapter := hls_protocol_control:hardware(), identity := binary()}.

-doc "Source partition and device bindings, parameterized only by the owning build stage's concrete endpoint binding.".
-type application(Binding) :: #{partition := partition(), devices := #{hls_source_config:device() => Binding}}.

-doc "The static host application returned by bind/4, before any device hardware is emitted.".
-type application() :: application(binding()).

%% Ordinary application bindings and the whole-gateway stage wrappers share these consumers.
-type checked_application() :: application(binding() | gateway() | attached_gateway()) |
    hls_protocol_application:descriptor() | hls_protocol_application:result().
%% Standalone selection needs coordinates, codecs and indices, without the full actor inventory.
-type selection_recipient() :: #{module := module(), index := non_neg_integer(),
    device := hls_source_config:device(), point := [non_neg_integer()],
    targets := [hls_protocol_topology:id()], id => hls_protocol_topology:id()}.
%% The independent selector accepts a checked ingress without the surrounding topology graph.
-type selection_ingress() :: #{id := hls_protocol_topology:id(), shape := [pos_integer()],
    targets := [target()], bindings := [selection_recipient()]}.
%% Device addresses are optional for selection itself and used by the shared wire-command caller.
-type selection_application() :: #{partition := #{ingresses := [selection_ingress()]},
    devices => #{hls_source_config:device() => #{host := hls_source_config:endpoint(),
        control := hls_source_config:endpoint(), ingress := hls_protocol_topology:id()}}}.
%% Full generated bindings and the standalone selector have distinct, concrete input shapes.
-type control_view() :: checked_application() | selection_application().

-doc "Checks loaded codecs against fresh source records and binds every actor to exactly one supplied device. Control is the unchanged whole plan from that same source build, never a native projection. Hosts supply positive 16-bit addresses. External schemas include only that device's actual producers. Returns typed control and event bindings; transport identities and admission remain the caller's responsibility.".
-spec bind(hls_protocol_transport:bundle(), none | hls_protocol_control:plan(),
    #{hls_protocol_topology:id() => hls_source_config:device()},
    #{hls_source_config:device() => hls_source_config:endpoint()}) -> application().
bind(#{frame_layout := Layout, topology := Topology = #{actors := Actors, routes := Routes, externals := Externals},
        modules := Modules}, Control, Owners, Hosts) ->
    ok = check_ownership(Actors, Owners, Hosts),
    Interfaces = checked_interfaces(Modules),
    ok = check_externals(Topology, Modules, Interfaces),
    Bound = bind_actors(Actors, Owners),
    Ingresses = hls_protocol_control:host_ingresses(Control, Bound),
    PortRoutes = [R#{source := {{actor, Id}, Port}} || R = #{source := {Id, Port}} <- Routes],
    Ports = [E#{port => "external_" ++ integer_to_list(I)} || {I, E} <- lists:enumerate(0, Externals)],
    Partition = #{frame_layout => Layout, actors => Bound, routes => PortRoutes, ingresses => Ingresses},
    Devices = maps:map(fun(Device, Host) ->
        Raw = hls_partition_wire:binding(Partition, Device, Host,
            #{ingresses => Ingresses, externals => Ports}),
        (maps:remove(identity, Raw))#{frame_layout => Layout, activation => explicit_start}
    end, Hosts),
    #{partition => Partition, devices => Devices}.

%% An application binding covers every actor and exactly the devices that own them.
-spec check_ownership([hls_protocol_topology:actor()],
    #{hls_protocol_topology:id() => hls_source_config:device()},
    #{hls_source_config:device() => hls_source_config:endpoint()}) -> ok.
check_ownership(Actors, Owners, Hosts) ->
    true = lists:sort(maps:keys(Owners)) =:= lists:sort([Id || #{id := Id} <- Actors]),
    true = lists:sort(maps:keys(Hosts)) =:= lists:usort(maps:values(Owners)),
    ok.

%% Loaded codecs must agree with the same fresh program that supplied the hardware layouts.
-spec checked_interfaces(#{module() => hls_local_actor:source() | hls_local_actor:artifact()}) ->
    #{module() => hls_actor_interface:summary()}.
checked_interfaces(Modules) ->
    Interfaces = hls_actor_interface:from_modules(maps:keys(Modules)),
    maps:foreach(fun(Module, Actor) -> check_codec(Module, Actor, maps:get(Module, Interfaces)) end, Modules),
    Interfaces.

%% Global source order defines indices independently of role names and sparse native placement.
-spec bind_actors([hls_protocol_topology:actor()],
    #{hls_protocol_topology:id() => hls_source_config:device()}) -> [actor()].
bind_actors(Actors, Owners) ->
    [A#{identity => {actor, Id}, index => I, device => maps:get(Id, Owners)}
        || {I, A = #{id := Id}} <- lists:enumerate(0, Actors)].

-doc "Encodes a typed rectangle using the checked source schemas. All selected devices must share the same command bytes. The relay broadcasts those global bounds; each native sparse mask discards unowned targets. An empty selection or malformed command is rejected before queue admission.".
-spec control(control_view(), hls_partition_wire:rectangle()) -> binary().
control(Application, Command) ->
    {Payload, _, _} = delivery(Application, Command),
    Payload.

-doc "Returns one checked command payload, its exact global actor indices and the original record. Uses the shared partition selector for schema packing and geometry; host owners filter these indices by actual local ownership. Rejects empty selection before queue admission. No transport or actor delivery occurs here.".
-spec delivery(control_view(), hls_partition_wire:rectangle()) -> {binary(), [non_neg_integer()], tuple()}.
delivery(#{partition := Partition}, {Ingress, Target, Bounds, Record}) ->
    #{packet := Packet, recipients := Recipients = [_ | _]} =
        hls_partition_ingress:select(Partition, Ingress, Target, Bounds, Record),
    {hls_partition_wire:control_payload(Packet), [maps:get(index, Actor) || Actor <- Recipients], Record}.

-doc "Decodes a canonical external frame at the emitted global endpoint index, using only the emitting device's producer schemas. Rejects unknown selectors, wrong word counts and noncanonical padding. This is codec validation, not application-semantic validation.".
-spec event(checked_application(), hls_source_config:device(), byte(), non_neg_integer()) ->
    {hls_protocol_topology:id(), tuple()}.
event(#{devices := Devices}, Device, Index, Frame) ->
    Binding = #{host := Host, events := Events, frame_layout := Layout} = maps:get(Device, Devices),
    Port = "external_" ++ integer_to_list(Index),
    [Endpoint] = [E || {E, #{port := P}} <- maps:to_list(Events), P =:= Port],
    {#{op := Tag, txid := 0, flags := 0}, Payload} = hls_frame_layout:unpack_integer(Layout, Frame),
    hls_partition_wire:event(Binding, {Endpoint, Host}, {Tag, 0, 0}, Payload).

%% Field names/order, types, selectors and packed width must match fresh compiler records.
-spec check_codec(module(), hls_local_actor:source() | hls_local_actor:artifact(), hls_actor_interface:summary()) -> ok.
check_codec(Module, #{program := Program}, Interface) ->
    #{message_names := Names} = xls_actor_program:spec(Program),
    Records = xls_statem_plan:records(xls_actor_program:plan(Program)),
    lists:foreach(fun({Op, Name}) ->
        #{selector := Op, fields := Fields} = hls_actor_interface:schema(Interface, Name),
        Op = Module:pack_tag(Name),
        Record = hls_records:find(Records, Name),
        Layout = hls_records:fields(Record),
        Layout = [{N, T} || #{name := N, type := T} <- Fields],
        Width = hls_records:width(Record),
        Width = Module:pack_width(Name)
    end, lists:enumerate(3, Names)).

%% A host event selector cannot ambiguously identify different producers' record layouts.
-spec check_externals(hls_protocol_topology:plan(), #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    #{module() => hls_actor_interface:summary()}) -> ok.
check_externals(#{actors := Actors, routes := Routes, externals := Externals}, Modules, Interfaces) ->
    ById = maps:from_list([{Id, Module} || #{id := Id, module := Module} <- Actors]),
    lists:foreach(fun(#{id := External}) ->
        Producers = [Source || #{source := Source, recipients := Recipients} <- Routes,
            lists:member({external, External}, Recipients)],
        Domains = lists:append([producer_domains(Source, ById, Modules, Interfaces) || Source <- Producers]),
        _ = lists:foldl(fun(Domain, Seen) -> check_event_selector(External, Domain, Seen) end, #{}, Domains),
        ok
    end, Externals).

%% Schema identity includes ordered field names and provider types, not merely payload width.
-type event_domain() :: #{mask := non_neg_integer(), value := non_neg_integer(),
    tag := atom(), schema_sha256 := binary()}.

%% Resolve a producer port through the checked interface before asking its source for wire domains.
-spec producer_domains({hls_protocol_topology:id(), atom()}, #{hls_protocol_topology:id() => module()},
    #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    #{module() => hls_actor_interface:summary()}) -> [event_domain()].
producer_domains({Id, Port}, ById, Modules, Interfaces) ->
    Module = maps:get(Id, ById),
    Tags = hls_actor_interface:output_schemas(maps:get(Module, Interfaces), Port),
    hls_protocol_schema:domains(maps:get(Module, Modules), Tags).

%% Multiple producers may share a selector only when their complete source domains agree.
-spec check_event_selector(hls_protocol_topology:id(), event_domain(), #{byte() => event_domain()}) ->
    #{byte() => event_domain()}.
check_event_selector(External, Domain = #{value := Value}, Seen) ->
    Op = (Value bsr 24) band 255,
    case maps:find(Op, Seen) of
        error -> Seen#{Op => Domain};
        {ok, Domain} -> Seen;
        {ok, _} -> error({ambiguous_application_event, External, Op})
    end.
