-module(hls_protocol_application_binding).
-moduledoc "Build-time source checks and derivation of retained application schemas. This boundary compares fresh compiler programs with loaded actor interfaces; host sessions use hls_protocol_application_codec without either input.".

%% Binding derivation owns source validation; runtime descriptor types have their own authority.
-export([bind/4]).
-export_type([gateway/0, attached_gateway/0]).

-doc "A whole-application host binding with its checked framed control adapter; emitted attachment identity is still absent.".
-type gateway() :: #{host := hls_protocol_application_schema:endpoint(), control := hls_protocol_application_schema:endpoint(),
    ingress := hls_protocol_application_schema:id(), events := #{hls_protocol_application_schema:endpoint() => hls_protocol_application_schema:event()},
    frame_layout := hls_frame_layout:layout(), activation := explicit_start, control_adapter := hls_protocol_control:hardware()}.

-doc "The emitted whole-application binding, with the exact hardware attachment identity required by the stream client.".
-type attached_gateway() :: #{host := hls_protocol_application_schema:endpoint(), control := hls_protocol_application_schema:endpoint(),
    ingress := hls_protocol_application_schema:id(), events := #{hls_protocol_application_schema:endpoint() => hls_protocol_application_schema:event()},
    frame_layout := hls_frame_layout:layout(), activation := explicit_start, control_adapter := hls_protocol_control:hardware(), identity := binary()}.

-doc "Checks loaded codecs against fresh source records and binds every actor to exactly one supplied device. Control is the unchanged whole plan from that same source build, never a native projection. Hosts supply positive 16-bit addresses. External schemas include only that device's actual producers. Returns typed control and event bindings; transport identities and admission remain the caller's responsibility.".
-spec bind(hls_protocol_transport:bundle(), none | hls_protocol_control:plan(),
    #{hls_protocol_topology:id() => hls_source_config:device()},
    #{hls_source_config:device() => hls_source_config:endpoint()}) -> hls_protocol_application_schema:application().
bind(#{frame_layout := Layout, topology := Topology = #{actors := Actors, routes := Routes, externals := Externals},
        modules := Modules}, Control, Owners, Hosts) ->
    ok = check_ownership(Actors, Owners, Hosts),
    Interfaces = checked_interfaces(Modules),
    ok = check_externals(Topology, Modules, Interfaces),
    Bound = bind_actors(Actors, Owners, Interfaces),
    Ingresses = hls_protocol_control:host_ingresses(Control, Bound),
    PortRoutes = [R#{source := {{actor, Id}, Port}} || R = #{source := {Id, Port}} <- Routes],
    Ports = [E#{port => "external_" ++ integer_to_list(I)} || {I, E} <- lists:enumerate(0, Externals)],
    Partition = #{frame_layout => Layout, actors => Bound, routes => PortRoutes, ingresses => Ingresses},
    Devices = maps:map(fun(Device, Host) ->
        Raw = hls_partition_binding:binding(Partition, Device, Host,
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
    #{hls_protocol_topology:id() => hls_source_config:device()},
    #{module() => hls_actor_interface:summary()}) -> [hls_protocol_application_schema:actor()].
bind_actors(Actors, Owners, Interfaces) ->
    Codecs = maps:map(fun(_, Interface) ->
        #{schemas => hls_host_codec:schemas(Interface),
            output_schemas => hls_host_codec:outputs(Interface)}
    end, Interfaces),
    [(maps:merge(A, maps:get(Module, Codecs)))#{identity => {actor, Id},
        index => I, device => maps:get(Id, Owners)} || {I, A = #{id := Id, module := Module}} <- lists:enumerate(0, Actors)].

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
