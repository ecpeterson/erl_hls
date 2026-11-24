-module(hls_deployment_artifact_tests).
-moduledoc "Versioned deployment artifacts retain only validated static runtime bindings.".
-include_lib("eunit/include/eunit.hrl").

%% Every public stream kind has stable deterministic bytes and an execution-only projection.
-spec roundtrip_test() -> ok.
roundtrip_test() ->
    Cases = [
        {partition_application, partition_candidate()},
        {protocol_deployment, protocol_candidate()},
        {mixed_application, mixed_candidate()}
    ],
    lists:foreach(
        fun({Kind, Candidate}) ->
            Artifact = hls_deployment_artifact:new(Kind, Candidate),
            Bytes = hls_deployment_artifact:encode(Artifact),
            ?assertEqual({ok, Artifact}, hls_deployment_artifact:decode(Bytes)),
            ?assertEqual(Kind, hls_deployment_artifact:kind(Artifact)),
            ?assertEqual(64, byte_size(hls_deployment_artifact:identity(Artifact))),
            Descriptor = hls_deployment_artifact:descriptor(Kind, Artifact),
            ?assertNot(maps:is_key(eligible, Descriptor)),
            ?assertNot(maps:is_key(source_boundary, Descriptor)),
            ?assertNot(maps:is_key(directories, Descriptor)),
            ?assertNot(maps:is_key(bridge, Descriptor))
        end,
        Cases
    ),
    ok.

%% Mixed crossing projection excludes source-only module identities from runtime bytes.
-spec mixed_projection_test() -> ok.
mixed_projection_test() ->
    Artifact = hls_deployment_artifact:new(mixed_application, mixed_candidate()),
    #{mixed := #{links := Links}} =
        hls_deployment_artifact:descriptor(mixed_application, Artifact),
    [?assertNot(maps:is_key(source_module, Link)) || Link <- Links],
    [?assertNot(maps:is_key(destination_module, Link)) || Link <- Links],
    ok.

%% Safe canonical decoding rejects executable terms, suffixes, compression and unsupported shape.
-spec decoding_rejection_test() -> ok.
decoding_rejection_test() ->
    Artifact = hls_deployment_artifact:new(partition_application, partition_candidate()),
    Bytes = hls_deployment_artifact:encode(Artifact),
    UnknownAtom = <<"hls_deployment_unknown_atom_5f35d0b4">>,
    Unsafe = <<131, 119, (byte_size(UnknownAtom)), UnknownAtom/binary>>,
    ?assertEqual({error, invalid_encoding}, hls_deployment_artifact:decode(Unsafe)),
    ?assertEqual({error, trailing_data}, hls_deployment_artifact:decode(<<Bytes/binary, 0>>)),
    ?assertEqual(
        {error, noncanonical_encoding},
        hls_deployment_artifact:decode(term_to_binary(Artifact, [compressed]))
    ),
    Extra = Artifact#{unexpected => true},
    ?assertEqual(
        {error, invalid_shape},
        hls_deployment_artifact:decode(term_to_binary(Extra, [deterministic]))
    ),
    ok.

%% The decoder bounds even trusted local input before ETF allocation or validation.
-spec oversized_decode_test_() -> term().
oversized_decode_test_() ->
    {timeout, 30, fun() ->
        Oversized = <<0:(64 * 1024 * 1024 + 1)/unit:8>>,
        ?assertEqual({error, artifact_too_large}, hls_deployment_artifact:decode(Oversized))
    end}.

%% A wrong retained attachment identity cannot become a valid runtime deployment.
-spec tampered_identity_test() -> ok.
tampered_identity_test() ->
    Artifact = hls_deployment_artifact:new(protocol_deployment, protocol_candidate()),
    Descriptor0 = hls_deployment_artifact:descriptor(protocol_deployment, Artifact),
    #{devices := Devices0} = Descriptor0,
    North = maps:get(north, Devices0),
    Descriptor = Descriptor0#{devices := Devices0#{north := North#{identity := <<0>>}}},
    Changed = Artifact#{descriptor := Descriptor},
    ?assertEqual(
        {error, invalid_attachment_identity},
        hls_deployment_artifact:decode(term_to_binary(Changed, [deterministic]))
    ),
    ok.

%% Raw relay artifacts omit application codecs while retaining their checked wire interface.
-spec raw_protocol_artifact_test() -> ok.
raw_protocol_artifact_test() ->
    Raw = maps:remove(application, protocol_candidate()),
    Artifact = hls_deployment_artifact:new(protocol_deployment, Raw),
    #{application := none, devices := Devices} =
        hls_deployment_artifact:descriptor(protocol_deployment, Artifact),
    ?assertEqual(1, maps:get(external_count, maps:get(north, Devices))),
    ?assertEqual(
        {ok, Artifact},
        hls_deployment_artifact:decode(
            hls_deployment_artifact:encode(Artifact)
        )
    ),
    #{devices := RawDevices} = Raw,
    North = maps:get(north, RawDevices),
    CrossingOnly = Raw#{devices := RawDevices#{north := North#{externals := []}}},
    CrossingArtifact = hls_deployment_artifact:new(protocol_deployment, CrossingOnly),
    #{devices := CrossingDevices} =
        hls_deployment_artifact:descriptor(protocol_deployment, CrossingArtifact),
    ?assertEqual(0, maps:get(external_count, maps:get(north, CrossingDevices))),
    ok.

%% Safe ETF still admits process capabilities; recursive validation rejects them in opaque IDs.
-spec ephemeral_term_rejection_test() -> ok.
ephemeral_term_rejection_test() ->
    Artifact = hls_deployment_artifact:new(partition_application, partition_candidate()),
    #{descriptor := Descriptor0 = #{partition := Partition0}} = Artifact,
    #{ingresses := [Ingress0]} = Partition0,
    #{targets := [Target0]} = Ingress0,
    lists:foreach(
        fun({Term, Kind}) ->
            Target = Target0#{id := Term},
            Ingress = Ingress0#{targets := [Target]},
            Partition = Partition0#{ingresses := [Ingress]},
            Changed = Artifact#{descriptor := Descriptor0#{partition := Partition}},
            Expected = {error, {ephemeral_term, Kind}},
            ?assertEqual(Expected, hls_deployment_artifact:validate(Changed)),
            ?assertEqual(
                Expected,
                hls_deployment_artifact:decode(
                    term_to_binary(Changed, [deterministic])
                )
            )
        end,
        [{self(), pid}, {make_ref(), reference}]
    ),
    ok.

%% Runtime rectangle selectors require exact two-axis geometry and singleton IDs.
-spec partition_structure_rejection_test() -> ok.
partition_structure_rejection_test() ->
    Artifact = hls_deployment_artifact:new(partition_application, partition_candidate()),
    #{descriptor := Descriptor0 = #{partition := Partition0, devices := Devices0}} = Artifact,
    #{ingresses := [Ingress0]} = Partition0,
    #{targets := [Target0], bindings := [Recipient0]} = Ingress0,
    #{schemas := Schemas0} = Recipient0,
    Sample0 = maps:get(sample, Schemas0),
    Board0 = maps:get(board, Devices0),
    Descriptors = [
        Descriptor0#{partition := Partition0#{frame_layout := #{payload_words => 0}}},
        Descriptor0#{
            partition := Partition0#{frame_layout := #{payload_words => 3, extra => true}}
        },
        Descriptor0#{
            devices := Devices0#{
                board := Board0#{
                    frame_layout := #{payload_words => 3, extra => true}
                }
            }
        },
        Descriptor0#{partition := Partition0#{ingresses := [Ingress0#{shape := [2]}]}},
        Descriptor0#{
            partition := Partition0#{
                ingresses := [
                    Ingress0#{
                        shape := [(1 bsl 16) + 1, 1],
                        bindings := [Recipient0#{point := [1 bsl 16, 0]}]
                    }
                ]
            }
        },
        Descriptor0#{
            partition := Partition0#{
                ingresses := [
                    Ingress0#{
                        bindings := [Recipient0#{point := [0]}]
                    }
                ]
            }
        },
        Descriptor0#{partition := Partition0#{ingresses := [Ingress0, Ingress0]}},
        Descriptor0#{
            partition := Partition0#{
                ingresses := [
                    Ingress0#{
                        targets := [Target0, Target0]
                    }
                ]
            }
        },
        Descriptor0#{
            partition := Partition0#{
                ingresses := [
                    Ingress0#{
                        bindings := [
                            Recipient0#{
                                schemas := Schemas0#{
                                    sample := maps:remove(selector, Sample0)
                                }
                            }
                        ]
                    }
                ]
            }
        },
        Descriptor0#{
            partition := Partition0#{
                ingresses := [
                    Ingress0#{
                        bindings := [
                            Recipient0#{
                                schemas := Schemas0#{
                                    sample := Sample0#{
                                        width := 0,
                                        codec := #{name => sample, fields => [garbage], width => 0}
                                    }
                                }
                            }
                        ]
                    }
                ]
            }
        }
    ],
    [rejected(Artifact#{descriptor := Descriptor}) || Descriptor <- Descriptors],
    ok.

%% Typed protocol events bind every physical external index to one retained event port.
-spec typed_external_contract_test() -> ok.
typed_external_contract_test() ->
    Artifact = hls_deployment_artifact:new(protocol_deployment, protocol_candidate()),
    #{descriptor := Descriptor0 = #{application := Application0, devices := Devices0}} = Artifact,
    Frame = hls_frame_layout:pack_integer(
        hls_frame_layout:default(),
        3,
        hls_record_codec:pack(record(), {sample, 42})
    ),
    ?assertEqual(
        {output, {sample, 42}},
        hls_protocol_application_codec:event(Application0, north, 0, Frame)
    ),
    #{partition := ApplicationPartition0, devices := ApplicationDevices0} = Application0,
    North0 = maps:get(north, ApplicationDevices0),
    #{events := Events0} = North0,
    Event0 = maps:get(8, Events0),
    BadApplication = Application0#{
        devices := ApplicationDevices0#{
            north := North0#{
                events := Events0#{8 := Event0#{port := "external_1"}}
            }
        }
    },
    rejected(Artifact#{descriptor := Descriptor0#{application := BadApplication}}),
    WideLayout = hls_frame_layout:new(4),
    WideApplication = Application0#{
        partition := ApplicationPartition0#{frame_layout := WideLayout},
        devices := maps:map(
            fun(_, Binding) -> Binding#{frame_layout := WideLayout} end, ApplicationDevices0
        )
    },
    rejected(Artifact#{descriptor := Descriptor0#{application := WideApplication}}),
    ProtocolNorth0 = maps:get(north, Devices0),
    #{links := [Link0 = #{classes := [Class0 = #{codec := Codec0}]}]} = ProtocolNorth0,
    BadLink = Link0#{
        classes := [
            Class0#{
                codec := Codec0#{
                    frame_layout := #{payload_words => 3, extra => true}
                }
            }
        ]
    },
    rejected(Artifact#{
        descriptor := Descriptor0#{
            devices := Devices0#{
                north := ProtocolNorth0#{
                    links := [BadLink]
                }
            }
        }
    }),
    ok.

%% Mixed startup cannot partially connect before every actor output has a virtual target.
-spec mixed_target_rejection_test() -> ok.
mixed_target_rejection_test() ->
    Artifact = hls_deployment_artifact:new(mixed_application, mixed_candidate()),
    #{descriptor := Descriptor0 = #{actors := Actors0}} = Artifact,
    Frame = hls_frame_layout:pack_integer(
        hls_frame_layout:default(),
        3,
        hls_record_codec:pack(record(), {sample, 7})
    ),
    ?assertEqual(
        {output, {sample, 7}},
        hls_protocol_mixed_host:native_event(
            Descriptor0, 0, Frame
        )
    ),
    ?assertError(
        {badmatch, false},
        hls_protocol_mixed_host:native_event(
            Descriptor0, 1, Frame
        )
    ),
    Actor0 = maps:get(0, Actors0),
    MissingTarget = Descriptor0#{
        actors := Actors0#{
            0 := Actor0#{
                outputs := #{out => {external, missing}}
            }
        }
    },
    rejected(Artifact#{descriptor := MissingTarget}),
    #{schemas := Schemas0} = Actor0,
    Sample0 = maps:get(sample, Schemas0),
    BadCatalog = Descriptor0#{
        actors := Actors0#{
            0 := Actor0#{
                schemas := Schemas0#{sample := Sample0#{selector := 256}}
            }
        }
    },
    rejected(Artifact#{descriptor := BadCatalog}),
    BadStartup = Descriptor0#{actors := Actors0#{0 := Actor0#{startup := [{sample, 256}]}}},
    rejected(Artifact#{descriptor := BadStartup}),
    ok.

%% Cross-field ownership and route checks reject values that would fail after partial startup.
-spec runtime_relation_rejection_test() -> ok.
runtime_relation_rejection_test() ->
    ProtocolArtifact = hls_deployment_artifact:new(protocol_deployment, protocol_candidate()),
    #{descriptor := ProtocolDescriptor0 = #{application := Application0, devices := Devices0}} =
        ProtocolArtifact,
    #{partition := ProtocolPartition0, devices := ApplicationDevices0} = Application0,
    NorthDevice0 = maps:get(north, Devices0),
    SouthDevice0 = maps:get(south, Devices0),
    NorthApplicationBinding0 = maps:get(north, ApplicationDevices0),
    SouthApplicationBinding0 = maps:get(south, ApplicationDevices0),
    SharedHost = maps:get(host, NorthDevice0),
    rejected(ProtocolArtifact#{
        descriptor := ProtocolDescriptor0#{
            devices := Devices0#{south := SouthDevice0#{host := SharedHost}},
            application := Application0#{
                devices := ApplicationDevices0#{
                    south := SouthApplicationBinding0#{host := SharedHost}
                }
            }
        }
    }),
    #{ingresses := [ProtocolIngress0]} = ProtocolPartition0,
    #{bindings := ProtocolRecipients0} = ProtocolIngress0,
    NorthRecipients = [
        Recipient
     || Recipient = #{device := north} <- ProtocolRecipients0
    ],
    SouthRecipients = [
        Recipient
     || Recipient = #{device := south} <- ProtocolRecipients0
    ],
    NorthIngress = ProtocolIngress0#{id := north_host, bindings := NorthRecipients},
    SouthIngress = ProtocolIngress0#{id := south_host, bindings := SouthRecipients},
    NorthBinding0 = NorthApplicationBinding0,
    [SouthRecipient0] = SouthRecipients,
    #{schemas := SouthSchemas0} = SouthRecipient0,
    SouthSample0 = maps:get(sample, SouthSchemas0),
    MismatchedIngress = ProtocolIngress0#{
        bindings := NorthRecipients ++
            [
                SouthRecipient0#{
                    schemas := SouthSchemas0#{sample := SouthSample0#{selector := 4}}
                }
            ]
    },
    rejected(ProtocolArtifact#{
        descriptor := ProtocolDescriptor0#{
            application := Application0#{
                partition := ProtocolPartition0#{ingresses := [MismatchedIngress]}
            }
        }
    }),
    DuplicateIngress = ProtocolIngress0#{id := duplicate_north, bindings := NorthRecipients},
    rejected(ProtocolArtifact#{
        descriptor := ProtocolDescriptor0#{
            application := Application0#{
                partition := ProtocolPartition0#{ingresses := [ProtocolIngress0, DuplicateIngress]}
            }
        }
    }),
    BadMembership = Application0#{
        partition := ProtocolPartition0#{ingresses := [NorthIngress, SouthIngress]},
        devices := ApplicationDevices0#{north := NorthBinding0#{ingress := south_host}}
    },
    rejected(ProtocolArtifact#{descriptor := ProtocolDescriptor0#{application := BadMembership}}),

    RawArtifact = hls_deployment_artifact:new(
        protocol_deployment, maps:remove(application, protocol_candidate())
    ),
    #{descriptor := RawDescriptor0 = #{devices := RawDevices0}} = RawArtifact,
    NorthDevice = maps:get(north, RawDevices0),
    SouthDevice = maps:get(south, RawDevices0),
    rejected(RawArtifact#{
        descriptor := RawDescriptor0#{
            devices := RawDevices0#{
                south := SouthDevice#{
                    host := maps:get(host, NorthDevice), service := maps:get(service, NorthDevice)
                }
            }
        }
    }),

    MixedArtifact = hls_deployment_artifact:new(mixed_application, mixed_candidate()),
    #{descriptor := MixedDescriptor0 = #{mixed := Mixed0, targets := Targets0}} = MixedArtifact,
    #{links := MixedLinks0} = Mixed0,
    ToBeam = [Link || Link = #{direction := to_beam} <- MixedLinks0],
    ToRtl = [Link || Link = #{direction := to_rtl} <- MixedLinks0],
    rejected(MixedArtifact#{descriptor := MixedDescriptor0#{mixed := Mixed0#{links := ToRtl}}}),
    rejected(MixedArtifact#{descriptor := MixedDescriptor0#{mixed := Mixed0#{links := ToBeam}}}),
    [Rtl0] = ToRtl,
    rejected(MixedArtifact#{
        descriptor := MixedDescriptor0#{
            mixed := Mixed0#{links := [Rtl0#{index := 1 bsl 16} | ToBeam]}
        }
    }),
    rejected(MixedArtifact#{
        descriptor := MixedDescriptor0#{
            mixed := Mixed0#{
                links := MixedLinks0 ++ [Rtl0#{index := 11}]
            }
        }
    }),
    rejected(MixedArtifact#{
        descriptor := MixedDescriptor0#{
            targets := Targets0#{{external, missing} => {external, missing}}
        }
    }),
    ok.

%% Compact permutations and rectangle records must match their exact runtime encoders.
-spec codec_relation_rejection_test() -> ok.
codec_relation_rejection_test() ->
    Artifact = hls_deployment_artifact:new(protocol_deployment, protocol_candidate()),
    #{descriptor := Descriptor0 = #{devices := Devices0}} = Artifact,
    North0 = maps:get(north, Devices0),
    #{links := [Link0 = #{classes := [Class0 = #{codec := Codec0}]}]} = North0,
    #{physical_width := PhysicalWidth, frame_positions := [Position | _], value := Value} = Codec0,
    Codecs = [
        Codec0#{physical_width := PhysicalWidth + 1},
        Codec0#{mask := 0},
        Codec0#{value := Value bor (1 bsl Position)},
        Codec0#{operation := (maps:get(operation, Codec0) + 1) band 255},
        compact_codec(hls_frame_layout:new(4))
    ],
    [
        rejected(Artifact#{
            descriptor := Descriptor0#{
                devices := Devices0#{
                    north := North0#{
                        links := [Link0#{classes := [Class0#{codec := Codec}]}]
                    }
                }
            }
        })
     || Codec <- Codecs
    ],

    PartitionArtifact = hls_deployment_artifact:new(
        partition_application, partition_candidate()
    ),
    #{descriptor := PartitionDescriptor0 = #{partition := Partition0, devices := PartitionDevices0}} =
        PartitionArtifact,
    #{ingresses := [Ingress0]} = Partition0,
    #{targets := [Target0], bindings := [Recipient0]} = Ingress0,
    WideRecord = hls_record_codec:bind(wide, [{value, hls_nums:uN(97)}]),
    WideSchema = #{name => wide, selector => 4, width => 97, codec => WideRecord},
    WideIngress = Ingress0#{
        targets := [Target0#{schemas := [wide]}],
        bindings := [Recipient0#{schemas := #{wide => WideSchema}}]
    },
    Board0 = maps:get(board, PartitionDevices0),
    Layout = hls_frame_layout:new(4),
    rejected(PartitionArtifact#{
        descriptor := PartitionDescriptor0#{
            partition := Partition0#{frame_layout := Layout, ingresses := [WideIngress]},
            devices := PartitionDevices0#{board := Board0#{frame_layout := Layout}}
        }
    }),

    MixedArtifact = hls_deployment_artifact:new(mixed_application, mixed_candidate()),
    #{descriptor := MixedDescriptor0 = #{actors := MixedActors0, mixed := Mixed0}} =
        MixedArtifact,
    MixedActor0 = maps:get(0, MixedActors0),
    MixedWideRecord = hls_record_codec:bind(sample, [{value, hls_nums:uN(97)}]),
    MixedWideSchema = #{
        name => sample, selector => 3, width => 97, codec => MixedWideRecord
    },
    #{links := MixedLinks0} = Mixed0,
    MixedWideLinks = [
        Link#{
            classes := [
                Class#{
                    message_bits := 97,
                    source_record := MixedWideRecord,
                    destination_record := MixedWideRecord
                }
             || Class <- maps:get(classes, Link)
            ]
        }
     || Link <- MixedLinks0
    ],
    rejected(MixedArtifact#{
        descriptor := MixedDescriptor0#{
            actors := MixedActors0#{0 := MixedActor0#{schemas := #{sample => MixedWideSchema}}},
            mixed := Mixed0#{links := MixedWideLinks}
        }
    }),
    ok.

%% A valid mixed external route is related to one board endpoint before its live event path runs.
-spec mixed_external_event_test() -> ok.
mixed_external_event_test() ->
    Candidate0 = mixed_candidate(),
    #{actors := Actors0, targets := Targets0} = Candidate0,
    Actor0 = maps:get(0, Actors0),
    Candidate = Candidate0#{
        actors := Actors0#{
            0 := Actor0#{
                outputs := (maps:get(outputs, Actor0))#{external => {external, output}},
                output_schemas := (maps:get(output_schemas, Actor0))#{external => [sample]}
            }
        },
        targets := Targets0#{{external, output} => {external, output}}
    },
    Artifact = hls_deployment_artifact:new(mixed_application, Candidate),
    Descriptor = hls_deployment_artifact:descriptor(mixed_application, Artifact),
    ?assertEqual(
        {output, {sample, 9}},
        hls_protocol_mixed_host:external(Descriptor, 0, output, {sample, 9})
    ),
    #{application := Application0} = Descriptor,
    #{devices := #{board := Board0 = #{events := Events0}}} = Application0,
    Event0 = maps:get(8, Events0),
    #{schemas := EventSchemas0} = Event0,
    EventSchema0 = maps:get(3, EventSchemas0),
    Signed = hls_record_codec:bind(sample, [{value, hls_nums:s8()}]),
    BadApplication = Application0#{
        devices := #{
            board => Board0#{
                events := Events0#{
                    8 := Event0#{schemas := EventSchemas0#{3 := EventSchema0#{codec := Signed}}}
                }
            }
        }
    },
    rejected(Artifact#{descriptor := Descriptor#{application := BadApplication}}),
    ok.

%% Every rejected artifact is checked before a stream can acquire a broker or actor.
-spec rejected(hls_deployment_artifact:artifact()) -> ok.
rejected(Artifact) ->
    ?assertMatch({error, _}, hls_deployment_artifact:validate(Artifact)),
    ok.

%% One real retained record layout supplies all synthetic application views.
-spec record() -> hls_record_codec:codec().
record() -> hls_record_codec:bind(sample, [{value, hls_nums:u8()}]).

%% Canonical host schema used by ingress, event and mixed actor checks.
-spec schemas() -> hls_host_codec:catalog().
schemas() ->
    Record = record(),
    #{sample => #{name => sample, selector => 3, width => 8, codec => Record}}.

%% Compact ordinary-frame projection used by protocol and mixed crossing classes.
-spec compact_codec() -> hls_protocol_codec:plan().
compact_codec() -> compact_codec(hls_frame_layout:default()).

%% An explicit layout lets regressions exercise bridge-incompatible canonical plans.
-spec compact_codec(hls_frame_layout:layout()) -> hls_protocol_codec:plan().
compact_codec(Layout) ->
    hls_protocol_codec_plan:plan(
        #{
            frame_layout => Layout,
            message_bits => 8,
            payload_bits => 8,
            fields => [
                #{
                    type => hls_nums:u8(),
                    message_bit_offset => 0,
                    capture_bit_offset => 0
                }
            ]
        },
        3,
        Layout
    ).

%% One two-point ingress retains only runtime geometry and record providers.
-spec partition([north | south | board]) -> map().
partition(Devices) ->
    Schemas = schemas(),
    #{
        frame_layout => hls_frame_layout:default(),
        actors => ignored_build_inventory,
        routes => ignored_build_routes,
        ingresses => [
            #{
                id => host,
                shape => [2, 1],
                targets => [#{id => all, selector => 0, schemas => [sample]}],
                bindings => [
                    #{
                        index => Index,
                        device => Device,
                        point => [Index, 0],
                        targets => [all],
                        schemas => Schemas,
                        module => ignored_build_module
                    }
                 || {Index, Device} <- lists:enumerate(0, Devices)
                ]
            }
        ]
    }.

%% Runtime application bindings intentionally contain target-only fields to be projected away.
-spec application([north | south | board]) -> map().
application(Devices) ->
    Hosts = #{north => 10, south => 11, board => 10},
    Bindings = maps:from_list([
        {Device, #{
            host => maps:get(Device, Hosts),
            control => 7,
            ingress => host,
            events => events(),
            frame_layout => hls_frame_layout:default(),
            activation => explicit_start,
            control_adapter => ignored_target_adapter
        }}
     || Device <- Devices
    ]),
    #{partition => partition(Devices), devices => Bindings}.

%% Each physical external index has one selector catalog and one canonical port name.
-spec events() -> map().
events() ->
    Schema = maps:get(sample, schemas()),
    #{8 => #{id => output, port => "external_0", schemas => #{3 => Schema}}}.

%% Single-device candidates add the per-gateway attachment identity and build-only boundary.
-spec partition_candidate() -> map().
partition_candidate() ->
    #{partition := Partition, devices := #{board := Binding}} = application([board]),
    #{
        partition => Partition,
        devices => #{board => Binding#{identity => <<1:256>>}},
        source_boundary => ignored_target_boundary,
        eligible => false
    }.

%% A paired crossing makes the two-role routing validator exercise both directions.
-spec protocol_candidate() -> map().
protocol_candidate() ->
    Class = #{slot => 0, codec => compact_codec(), capture => ignored_physical_field},
    Out = #{
        index => 4,
        direction => outgoing,
        source_index => 0,
        destination_index => 1,
        classes => [Class],
        slots => 1
    },
    In = Out#{direction := incoming},
    #{
        devices => #{
            north => protocol_device(10, 20, 0, Out),
            south => protocol_device(11, 21, 1, In)
        },
        actors => 2,
        limits => #{commands => 4, events => 4, crossings => 1},
        application => application([north, south]),
        directories => #{north => "role0", south => "role1"},
        eligible => false
    }.

%% Protocol role build metadata is deliberately larger than the runtime projection.
-spec protocol_device(pos_integer(), pos_integer(), non_neg_integer(), map()) -> map().
protocol_device(Host, Service, Index, Link) ->
    #{
        host => Host,
        service => Service,
        identity => <<Index:256>>,
        native_indices => [Index],
        externals => [#{index => 0, name => output}],
        links => [Link],
        libraries => ignored_build_libraries,
        control_adapter => ignored_target_adapter
    }.

%% One crossing in each direction exercises source ownership and bounded reverse delivery.
-spec mixed_candidate() -> map().
mixed_candidate() ->
    Record = record(),
    Class = #{
        slot => 0,
        codec => compact_codec(),
        port => out,
        tag => sample,
        message_bits => 8,
        source_record => Record,
        destination_record => Record,
        capture => ignored_physical_field
    },
    ToBeam = #{
        index => 9,
        source_index => 1,
        destination_index => 0,
        direction => to_beam,
        source_module => native_fixture,
        destination_module => host_fixture,
        classes => [Class],
        slots => 1
    },
    ToRtl = ToBeam#{
        index := 10,
        source_index := 0,
        destination_index := 1,
        direction := to_rtl,
        source_module := host_fixture,
        destination_module := native_fixture
    },
    Actor = #{
        id => ignored_logical_id,
        module => host_fixture,
        capacity => 2,
        outputs => #{out => {actor, native}},
        startup => [],
        schemas => schemas(),
        output_schemas => #{out => [sample]}
    },
    #{
        actors => #{0 => Actor},
        targets => #{{actor, native} => {actor, 1}},
        mixed => #{host_actors => [0], links => [ToBeam, ToRtl], identity => <<2:256>>},
        application => application([board]),
        binding => #{host => 10, control => 20},
        bridge => #{externals => [#{index => 0}], ignored => target_metadata},
        device => board,
        eligible => false
    }.
