-module(hls_protocol_domains).
-moduledoc """
Composes independently resettable source partitions with incarnation-bound mailbox channels.
Source topology owns actor routes and crossing codecs. This builder checks placement and
restart-group closure; hls_domain_channel_build supplies the shared channel policy and
sv_domain_channels connects only named ports. A group declaration is not an FPGA supervisor:
the host must retire its old endpoints and replace both crossing incarnations before rebinding.
Cold reset requires deployment exclusion of old transport. Optional framing gives each domain independent host lanes and keeps channel control on a separate management lane. Optional process inspection preserves global actor IDs on dedicated incarnation-checked pins in either mode.
""".

%% Checked composition and portable source publication.
-export([emit/2, emit_stream/2, write/3, write_stream/3]).
-export_type([placement/0, domain/0, crossing/0, result/0]).

-doc "At least two nonempty domains cover global actor indices exactly once; restart groups partition their atom IDs. Every crossing must remain inside one declared group.".
-type placement() :: #{
    domains := [{atom(), [non_neg_integer(), ...]}, ...],
    restart_groups := [[atom(), ...], ...]
}.
-doc "One checked domain index and its independently compiled raw interface.".
-type domain() :: #{
    id := atom(),
    index := non_neg_integer(),
    actors := [non_neg_integer(), ...],
    interface := hls_protocol_domain:result(),
    mode => raw | stream
}.
-doc "A directed source crossing and its two owning domain indices; the retained link uses outgoing orientation.".
-type crossing() :: #{
    index := non_neg_integer(),
    source_domain := non_neg_integer(),
    destination_domain := non_neg_integer(),
    link := xls_protocol_network:crossing()
}.
-doc "Source-derived placement, raw ports and exact domain/channel interfaces. Static group closure does not establish hardware fit or recovery progress.".
-type result() :: #{
    domains := [domain()],
    crossings := [crossing()],
    restart_groups := [[atom()]],
    inputs := [{string(), pos_integer()}],
    outputs := [{string(), pos_integer()}],
    codecs := hls_protocol_domain:codecs(),
    channel := hls_domain_channel_build:result(),
    frame_payload_words := hls_frame_layout:words(),
    eligible := false,
    channel_stream => hls_domain_channels_stream:result()
}.

-doc "Prepares one source snapshot and splits its topology by global actor indices. Invokes the topology constructor once and renders every role from the retained programs. Validates disjoint coverage and restart-group closure before partition emission. Each real crossing uses one independent shared-policy channel; host ingress, lifecycle and effects remain separate per domain. Public channel transport ports require ordered, bounded deployment ownership. Rebinding requires both endpoint incarnations to be fresh; declarations do not automatically restart a group.".
-spec emit(hls_source_config:network() | file:filename(), placement()) ->
    hls_generated_files:output(result()).
emit(Config, Placement) -> compose(Config, Placement, raw).

-doc "Emits the same checked domain placement behind independent framed host endpoints and one channel-management stream. Requires at least one crossing. Channel data/credit ports retain their ordered external transport contract. Session changes preserve domain and channel ownership; this supplies no CDC or automatic group supervisor.".
-spec emit_stream(hls_source_config:network() | file:filename(), placement()) ->
    hls_generated_files:output(result()).
emit_stream(Config, Placement) -> compose(Config, Placement, stream).

%% Both public forms retain one prepared application and differ only at their external interfaces.
-spec compose(hls_source_config:network() | file:filename(), placement(), raw | stream) ->
    hls_generated_files:output(result()).
compose(Filename, Placement, Mode) when is_list(Filename); is_binary(Filename) ->
    compose(hls_source_config:read(Filename), Placement, Mode);
compose(Config0, Placement, Mode) when is_map(Config0) ->
    require(not maps:is_key(native_actors, Config0), complete_source_required),
    Words = max(20, maps:get(frame_payload_words, Config0, 3)),
    Config = hls_source_config:validate(network, Config0#{frame_payload_words => Words}),
    automatic = maps:get(activation, Config, automatic),
    Program = hls_protocol_transport:prepare(Config),
    Options = maps:with([arithmetic_groups], Config),
    Build = hls_protocol_transport:plan(Program, Options),
    #{bundle := #{topology := #{actors := Actors}}, fabric := #{links := Links}} =
        hls_protocol_transport:descriptor(Build),
    {Definitions, Groups, Owners} = placement(Placement, length(Actors), Links),
    require(
        Mode =:= raw orelse
            lists:any(
                fun(#{source_index := S, destination_index := D}) ->
                    maps:get(S, Owners) =/= maps:get(D, Owners)
                end,
                Links
            ),
        no_crossings
    ),
    Generated = [
        begin
            Ids = [maps:get(id, lists:nth(I + 1, Actors)) || I <- Indices],
            Partition = hls_protocol_transport:plan(Program, Options#{native_actors => Ids}),
            GeneratedDomain = domain_emit(Partition, Mode, maps:get(inspection, Config, none)),
            {Id, Index, Indices, GeneratedDomain}
        end
     || {Index, {Id, Indices}} <- lists:enumerate(0, Definitions)
    ],
    Domains = [
        #{id => Id, index => Index, actors => Indices, interface => Interface, mode => Mode}
     || {Id, Index, Indices, #{result := Interface}} <- Generated
    ],
    [#{interface := #{codecs := Codecs}} | _] = Domains,
    require(
        lists:all(fun(#{interface := #{codecs := C}}) -> C =:= Codecs end, Domains), domain_codecs
    ),
    Crossings = crossings(Domains, Owners),
    #{files := ChannelFiles, result := Channel} = hls_domain_channel_build:emit(Words),
    {Inputs, Outputs} = sv_domain_channels:ports(Domains, Crossings, Channel),
    Result = #{
        domains => Domains,
        crossings => Crossings,
        restart_groups => Groups,
        inputs => Inputs,
        outputs => Outputs,
        codecs => Codecs,
        channel => Channel,
        frame_payload_words => Words,
        eligible => false
    },
    Files = hls_generated_files:merge([
        domain_files(Generated, Mode),
        ChannelFiles,
        #{
            "channel/protocol_domains.sv" => sv_domain_channels:emit(
                Domains,
                Crossings,
                Channel,
                case Mode of
                    raw -> "protocol_domains";
                    stream -> "protocol_domains_stream_raw"
                end
            )
        }
    ]),
    case Mode of
        raw ->
            #{files => Files, result => Result};
        stream ->
            Management =
                #{files := ManagementFiles, inputs := FramedInputs, outputs := FramedOutputs} =
                hls_domain_channels_stream:emit(Result),
            #{
                files => hls_generated_files:merge([Files, ManagementFiles]),
                result => Result#{
                    inputs := FramedInputs,
                    outputs := FramedOutputs,
                    channel_stream => maps:remove(files, Management)
                }
            }
    end.

%% Framing wraps the same partition core; host schemas contain only that core's native actors.
-spec domain_emit(hls_protocol_transport:build(), raw | stream, none | process) ->
    hls_generated_files:output(hls_protocol_domain:result()).
domain_emit(Build, raw, Inspection) ->
    hls_protocol_domain:emit_partition_plan(Build, Inspection);
domain_emit(Build, stream, Inspection) ->
    #{
        files := Files,
        result := Domain = #{stream := Plan, codecs := Codecs, frame_payload_words := Words}
    } =
        hls_protocol_domain:emit_partition_stream_plan(Build, Inspection),
    Stream =
        #{files := StreamFiles, inputs := Inputs, outputs := Outputs} = hls_domain_stream:emit_partition(
            Domain
        ),
    Transport = maps:remove(files, Stream),
    Runtime = maps:merge(Plan, #{
        codecs => Codecs, frame_payload_words => Words, transport => Transport
    }),
    #{
        files => hls_generated_files:merge([Files, StreamFiles]),
        result => Domain#{
            inputs := Inputs,
            outputs := Outputs,
            transport => Transport,
            runtime_interface => Runtime
        }
    }.

%% Source membership and explicit restart policy are checked independently of HDL names.
-spec placement(placement(), non_neg_integer(), [hls_protocol_fabric:link()]) ->
    {[{atom(), [non_neg_integer()]}], [[atom()]], #{non_neg_integer() := non_neg_integer()}}.
placement(#{domains := Domains, restart_groups := Groups} = Placement, Count, Links) ->
    require(lists:sort(maps:keys(Placement)) =:= [domains, restart_groups], placement_fields),
    require(is_list(Domains) andalso length(Domains) >= 2, domains),
    require(
        lists:all(
            fun
                ({Id, Indices}) when is_atom(Id), is_list(Indices), Indices =/= [] ->
                    lists:all(
                        fun(I) -> is_integer(I) andalso I >= 0 andalso I < Count end, Indices
                    );
                (_) ->
                    false
            end,
            Domains
        ),
        domain_members
    ),
    Ids = [Id || {Id, _} <- Domains],
    require(length(Ids) =:= length(lists:usort(Ids)), duplicate_domain),
    require(
        lists:sort(lists:append([Is || {_, Is} <- Domains])) =:= lists:seq(0, Count - 1),
        actor_cover
    ),
    require(
        is_list(Groups) andalso Groups =/= [] andalso
            lists:all(
                fun(G) ->
                    is_list(G) andalso G =/= [] andalso lists:all(fun is_atom/1, G)
                end,
                Groups
            ),
        restart_groups
    ),
    require(lists:sort(lists:append(Groups)) =:= lists:sort(Ids), group_cover),
    Owners = maps:from_list([{I, D} || {D, {_, Is}} <- lists:enumerate(0, Domains), I <- Is]),
    GroupById = maps:from_list([
        {Id, G}
     || {G, Members} <- lists:enumerate(0, Groups), Id <- Members
    ]),
    GroupByActor = maps:from_list([{I, maps:get(Id, GroupById)} || {Id, Is} <- Domains, I <- Is]),
    lists:foreach(
        fun(#{source_index := S, destination_index := D}) ->
            require(maps:get(S, GroupByActor) =:= maps:get(D, GroupByActor), crossing_restart_group)
        end,
        Links
    ),
    {Domains, Groups, Owners};
placement(_, _, _) ->
    error({domain_composition, placement}).

%% Each outgoing descriptor must have exactly the same destination-derived incoming schema.
-spec crossings([domain()], #{non_neg_integer() := non_neg_integer()}) -> [crossing()].
crossings(Domains, Owners) ->
    Links = lists:append([Cs || #{interface := #{crossings := Cs}} <- Domains]),
    Outgoing = [C || C = #{direction := outgoing} <- Links],
    require(
        length(Outgoing) =:= length(lists:usort([I || #{index := I} <- Outgoing])),
        duplicate_crossing
    ),
    [
        begin
            [Incoming] = [C || C = #{index := J, direction := incoming} <- Links, J =:= I],
            require(
                maps:remove(direction, Incoming) =:= maps:remove(direction, Link), crossing_schema
            ),
            #{
                index => I,
                source_domain => maps:get(S, Owners),
                destination_domain => maps:get(D, Owners),
                link => Link
            }
        end
     || Link = #{index := I, source_index := S, destination_index := D} <- Outgoing
    ].

%% Checked numeric domain indices name HDL modules; source atom names remain in metadata.
-spec domain_files(
    [
        {
            atom(),
            non_neg_integer(),
            [non_neg_integer()],
            hls_generated_files:output(hls_protocol_domain:result())
        }
    ],
    raw | stream
) -> hls_generated_files:files().
domain_files(Generated, Mode) ->
    hls_generated_files:merge([
        begin
            Prefix = domain_name(Index),
            Wrapper =
                case Mode of
                    raw -> "domain/protocol_domain.sv";
                    stream -> "domain/domain_stream.sv"
                end,
            Renamed = Files#{
                Wrapper =>
                    sv_protocol_ports:emit(Inputs, Outputs, Prefix, Prefix ++ "_core")
            },
            hls_generated_files:prefix(Prefix, Renamed)
        end
     || {_, Index, _, #{files := Files, result := #{inputs := Inputs, outputs := Outputs}}} <-
            Generated
    ]).

-doc "Writes a fresh portable composite bundle with one XLS unit per domain and one shared channel unit. Configured dslx_path providers and support imports are checked before output creation and snapshotted independently for each source namespace; top-level RTL is mechanical wiring. Does not run tools, establish transport exclusion or start any domain.".
-spec write(hls_source_config:network() | file:filename(), placement(), file:filename()) -> map().
write(Config, Placement, Directory) -> write_bundle(Config, Placement, Directory, raw).

-doc "Writes the framed composition and matching per-domain runtime interfaces plus channel_management/interface.etf. Builds one independent XLS unit per domain, one shared channel implementation and one management parser. Does not attach brokers or start recovery.".
-spec write_stream(hls_source_config:network() | file:filename(), placement(), file:filename()) ->
    map().
write_stream(Config, Placement, Directory) -> write_bundle(Config, Placement, Directory, stream).

%% Normalize file inputs once; every namespace retains the configured provider snapshot.
-spec write_bundle(
    hls_source_config:network() | file:filename(), placement(), file:filename(), raw | stream
) -> map().
write_bundle(Filename, Placement, Directory, Mode) when is_list(Filename); is_binary(Filename) ->
    write_bundle(hls_source_config:read(Filename), Placement, Directory, Mode);
write_bundle(Config, Placement, Directory, Mode) when is_map(Config) ->
    Generated =
        #{result := Result = #{domains := Domains, frame_payload_words := Words}} = compose(
            Config, Placement, Mode
        ),
    #{libraries := Libraries, imports := Support} = hls_build_support:layout(
        maps:get(dslx_path, Config, [])
    ),
    _ = hls_generated_files:write(Generated, Directory),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    ok = hls_compile:configure_support(Directory, hls_frame_layout:new(Words)),
    Units = [
        begin
            Prefix = domain_name(Index),
            Root = filename:join(Directory, Prefix),
            ok = hls_artifact_bundle:snapshot(Root, Libraries),
            ok = hls_compile:configure_support(Root, hls_frame_layout:new(Words)),
            ok = file:write_file(
                filename:join([Root, "domain", "interface.etf"]),
                term_to_binary(maps:get(runtime_interface, Interface, Interface)),
                [
                    exclusive
                ]
            ),
            {Source, Top, Output, Wrapper} =
                case Mode of
                    raw ->
                        {"domain.x", "domain_clock", "core.v", "protocol_domain.sv"};
                    stream ->
                        {"domain_stream.x", "domain_stream_clock", "stream_core.v",
                            "domain_stream.sv"}
                end,
            unit(
                Prefix ++ "/domain",
                Prefix ++ "/domain/" ++ Source,
                Top,
                Prefix ++ "_core",
                Prefix ++ "/domain/" ++ Output,
                [Prefix ++ "/" ++ P || P <- ["domain", "network", "actors", "dslx"] ++ Support],
                [Prefix ++ "/domain/" ++ Output, Prefix ++ "/domain/" ++ Wrapper],
                Words
            )
        end
     || #{index := Index, interface := Interface} <- Domains
    ],
    ChannelUnit = unit(
        "channel",
        "channel/domain_channel.x",
        "channel_clock",
        "domain_channel_core",
        "channel/core.v",
        ["channel" | Support],
        ["channel/core.v", "channel/domain_channel.sv", "channel/protocol_domains.sv"],
        Words
    ),
    ok = file:write_file(filename:join(Directory, "interface.etf"), term_to_binary(Result), [
        exclusive
    ]),
    ManagementUnits =
        case Mode of
            raw ->
                [];
            stream ->
                #{channel_stream := #{interface := ManagementInterface, unit := ManagementUnit}} =
                    Result,
                ok = file:write_file(
                    filename:join([Directory, "channel_management", "interface.etf"]),
                    term_to_binary(ManagementInterface),
                    [exclusive]
                ),
                [ManagementUnit]
        end,
    hls_artifact_bundle:finish(
        Directory,
        Units ++ [ChannelUnit] ++ ManagementUnits,
        #{kind => domain_composition, backend => source_protocol}
    ).

%% Sampled-clock units share the frame profile while retaining independent import namespaces.
-spec unit(
    string(),
    string(),
    string(),
    string(),
    string(),
    [string()],
    [string()],
    hls_frame_layout:words()
) -> hls_artifact_bundle:unit().
unit(Directory, Source, Top, Module, Output, Imports, Rtl, Words) ->
    Profile = hls_build_profile:owner(hls_frame_layout:new(Words)),
    #{
        role => <<".">>,
        directory => b(Directory),
        source => b(Source),
        top => b(Top),
        module => b(Module),
        output => b(Output),
        dslx_path => [b(P) || P <- Imports],
        rtl => [b(P) || P <- Rtl],
        codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
    }.

%% Only elaborated numeric identities become filesystem or HDL components.
-spec domain_name(non_neg_integer()) -> string().
domain_name(Index) -> "domain_" ++ integer_to_list(Index).

%% Manifest paths are portable UTF-8 binaries.
-spec b(string()) -> binary().
b(Text) -> unicode:characters_to_binary(Text).

%% Rejected source/placement contracts do not create partially connected hardware.
-spec require(boolean(), atom()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({domain_composition, Reason}).
