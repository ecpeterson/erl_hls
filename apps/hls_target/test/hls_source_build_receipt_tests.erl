-module(hls_source_build_receipt_tests).
-moduledoc "Checked source-build receipt correlation and byte-tamper tests.".
-include_lib("eunit/include/eunit.hrl").

%% Exact receipt relations pass; changed identities, provenance or products reject.
-spec receipt_correlation_test() -> ok.
receipt_correlation_test() ->
    with_directory(fun(Root) ->
        {SourceBuild, Receipt} = fixture(Root),
        Implementation = maps:get(<<"sha256">>, maps:get(<<"implementation">>, Receipt)),
        ?assertEqual(
            #{implementation => Implementation, rtl => [<<"core.v">>]},
            hls_source_build_receipt:validate(Root, SourceBuild)
        ),
        ChangedImplementation = update(
            Receipt,
            <<"implementation">>,
            fun(Value) -> Value#{<<"sha256">> := binary:copy(<<"0">>, 64)} end
        ),
        rejected(Root, SourceBuild, ChangedImplementation),
        rejected(
            Root,
            SourceBuild,
            Receipt#{<<"source_build_sha256">> := binary:copy(<<"1">>, 64)}
        ),
        ChangedProducts = update(
            Receipt,
            <<"products">>,
            fun(Value) -> Value#{<<"sha256">> := binary:copy(<<"2">>, 64)} end
        ),
        rejected(Root, SourceBuild, ChangedProducts),
        ProductRows = maps:get(<<"files">>, maps:get(<<"products">>, Receipt)),
        rejected(Root, SourceBuild, reidentify_products(Receipt, tl(ProductRows))),
        Extra = <<"unrelated product\n">>,
        ok = file:write_file(filename:join(Root, "unexpected.bin"), Extra),
        ExtraRows = lists:sort(
            fun(A, B) -> maps:get(<<"file">>, A) =< maps:get(<<"file">>, B) end,
            [#{<<"file">> => <<"unexpected.bin">>, <<"sha256">> => hash(Extra)} | ProductRows]
        ),
        rejected(Root, SourceBuild, reidentify_products(Receipt, ExtraRows)),
        Rtl = maps:get(<<"rtl">>, Receipt),
        rejected(Root, SourceBuild, Receipt#{<<"rtl">> := Rtl#{<<"network">> := []}}),
        Request0 = maps:get(<<"descriptor">>, maps:get(<<"build_request">>, Receipt)),
        [RequestUnit0] = maps:get(<<"units">>, Request0),
        [Convert, Optimize, Codegen0] = maps:get(<<"commands">>, RequestUnit0),
        Codegen = Codegen0#{
            <<"arguments">> := [<<"--module_name=forged">>, <<"network/optimized.ir">>]
        },
        RequestUnit = RequestUnit0#{
            <<"module">> := <<"forged">>,
            <<"commands">> := [Convert, Optimize, Codegen]
        },
        Request = Request0#{<<"units">> := [RequestUnit]},
        rejected(Root, SourceBuild, reidentify_request(Receipt, Request)),
        OtherProvenance = #{
            <<"kind">> => <<"implementation_plan">>,
            <<"logical_system_sha256">> => binary:copy(<<"3">>, 64),
            <<"implementation_plan_sha256">> => binary:copy(<<"4">>, 64),
            <<"target_projection_sha256">> => binary:copy(<<"5">>, 64)
        },
        rejected(Root, SourceBuild, Receipt#{<<"provenance">> := OtherProvenance}),
        ok = write_receipt(Root, Receipt),
        ok = file:write_file(filename:join(Root, "core.v"), <<"changed product\n">>),
        ?assertError(
            {source_build_receipt, invalid_receipt},
            hls_source_build_receipt:validate(Root, SourceBuild)
        )
    end).

%% Build one internally consistent planned receipt using the production identity algorithm.
-spec fixture(file:filename()) -> {binary(), map()}.
fixture(Root) ->
    Provenance = #{
        <<"kind">> => <<"implementation_plan">>,
        <<"logical_system_sha256">> => binary:copy(<<"a">>, 64),
        <<"implementation_plan_sha256">> => binary:copy(<<"b">>, 64),
        <<"target_projection_sha256">> => binary:copy(<<"c">>, 64)
    },
    Metadata = #{<<"backend">> => <<"source_protocol">>},
    SourceRtl = #{<<"network">> => [<<"core.v">>]},
    SourceUnits = [
        #{
            <<"directory">> => <<"network">>,
            <<"role">> => <<"network">>,
            <<"source">> => <<"network.x">>,
            <<"top">> => <<"main">>,
            <<"module">> => <<"core">>,
            <<"output">> => <<"core.v">>,
            <<"dslx_path">> => [],
            <<"codegen_flags">> => [],
            <<"rtl">> => [<<"core.v">>]
        }
    ],
    SourceBuild = iolist_to_binary(
        json:encode(#{
            <<"version">> => 2,
            <<"metadata">> => Metadata,
            <<"provenance">> => Provenance,
            <<"inputs">> => [],
            <<"units">> => SourceUnits,
            <<"rtl">> => SourceRtl
        })
    ),
    ok = file:write_file(filename:join(Root, "source-build.json"), SourceBuild),
    ok = file:make_dir(filename:join(Root, "network")),
    Files = [
        {<<"core.v">>, <<"module core; endmodule\n">>},
        {<<"network/optimized.ir">>, <<"optimized proc p\n">>},
        {<<"network/raw.ir">>, <<"top proc p\n">>}
    ],
    lists:foreach(
        fun({Name, Bytes}) -> ok = file:write_file(filename:join(Root, Name), Bytes) end,
        Files
    ),
    ProductRows = [#{<<"file">> => Name, <<"sha256">> => hash(Bytes)} || {Name, Bytes} <- Files],
    ProductDescriptor = #{<<"schema">> => 1, <<"files">> => ProductRows},
    ProductIdentity = identity(ProductDescriptor),
    Products = ProductDescriptor#{<<"sha256">> => ProductIdentity},
    Tools = #{<<"codegen_main">> => binary:copy(<<"d">>, 64)},
    RequestUnits = [
        #{
            <<"directory">> => <<"network">>,
            <<"role">> => <<"network">>,
            <<"source">> => <<"network.x">>,
            <<"top">> => <<"main">>,
            <<"module">> => <<"core">>,
            <<"codegen_flags">> => [],
            <<"dslx_path">> => [],
            <<"commands">> => [
                #{
                    <<"stage">> => <<"convert">>,
                    <<"tool">> => <<"ir_converter_main">>,
                    <<"arguments">> => [
                        <<"--warnings_as_errors=false">>,
                        <<"--top=main">>,
                        <<"--dslx_path=">>,
                        <<"--dslx_stdlib_path=_stdlib">>,
                        <<"network.x">>
                    ],
                    <<"output">> => <<"network/raw.ir">>
                },
                #{
                    <<"stage">> => <<"opt">>,
                    <<"tool">> => <<"opt_main">>,
                    <<"arguments">> => [<<"network/raw.ir">>],
                    <<"output">> => <<"network/optimized.ir">>
                },
                #{
                    <<"stage">> => <<"codegen">>,
                    <<"tool">> => <<"codegen_main">>,
                    <<"arguments">> => [<<"--module_name=core">>, <<"network/optimized.ir">>],
                    <<"output">> => <<"core.v">>
                }
            ]
        }
    ],
    Request = #{
        <<"schema">> => 1,
        <<"executor_recipe">> => 1,
        <<"host">> => [<<"fixture">>, <<"fixture">>],
        <<"source_recipe_sha256">> => hash(SourceBuild),
        <<"tools">> => Tools,
        <<"stdlib">> => [],
        <<"units">> => RequestUnits,
        <<"rtl">> => SourceRtl
    },
    RequestIdentity = identity(Request),
    BuildRequest = #{
        <<"schema">> => 1, <<"sha256">> => RequestIdentity, <<"descriptor">> => Request
    },
    Realization = #{
        <<"schema">> => 1,
        <<"request_sha256">> => RequestIdentity,
        <<"product_sha256">> => ProductIdentity,
        <<"provenance">> => Provenance
    },
    Implementation = Realization#{<<"sha256">> => identity(Realization)},
    CoreRow = hd(ProductRows),
    Receipt = #{
        <<"version">> => 2,
        <<"source_build_sha256">> => hash(SourceBuild),
        <<"metadata">> => Metadata,
        <<"provenance">> => Provenance,
        <<"build_request">> => BuildRequest,
        <<"products">> => Products,
        <<"implementation">> => Implementation,
        <<"xls_tools">> => Tools,
        <<"units">> => [],
        <<"rtl">> => #{<<"network">> => [CoreRow]},
        <<"eligible">> => false,
        <<"native_measured">> => false
    },
    ok = write_receipt(Root, Receipt),
    {SourceBuild, Receipt}.

%% Recompute both identities after a deliberate complete product-record rewrite.
-spec reidentify_products(map(), [map()]) -> map().
reidentify_products(Receipt, Rows) ->
    ProductDescriptor = #{<<"schema">> => 1, <<"files">> => Rows},
    ProductIdentity = identity(ProductDescriptor),
    Products = ProductDescriptor#{<<"sha256">> => ProductIdentity},
    Implementation0 = maps:get(<<"implementation">>, Receipt),
    Realization = (maps:without([<<"sha256">>], Implementation0))#{
        <<"product_sha256">> := ProductIdentity
    },
    Receipt#{
        <<"products">> := Products,
        <<"implementation">> := Realization#{<<"sha256">> => identity(Realization)}
    }.

%% Recompute request, product and implementation identities after a descriptor rewrite.
-spec reidentify_request(map(), map()) -> map().
reidentify_request(Receipt, Request) ->
    RequestIdentity = identity(Request),
    BuildRequest = #{
        <<"schema">> => 1, <<"sha256">> => RequestIdentity, <<"descriptor">> => Request
    },
    ProductRows = maps:get(<<"files">>, maps:get(<<"products">>, Receipt)),
    Receipt0 = reidentify_products(Receipt, ProductRows),
    Implementation0 = maps:get(<<"implementation">>, Receipt0),
    Realization = (maps:without([<<"sha256">>], Implementation0))#{
        <<"request_sha256">> := RequestIdentity
    },
    Receipt0#{
        <<"build_request">> := BuildRequest,
        <<"implementation">> := Realization#{<<"sha256">> => identity(Realization)}
    }.

%% Replace only the tested receipt and require the stable invalid-receipt boundary.
-spec rejected(file:filename(), binary(), map()) -> ok.
rejected(Root, SourceBuild, Receipt) ->
    ok = write_receipt(Root, Receipt),
    ?assertError(
        {source_build_receipt, invalid_receipt},
        hls_source_build_receipt:validate(Root, SourceBuild)
    ).

%% Change one nested receipt component without obscuring the tested relation.
-spec update(map(), binary(), fun((map()) -> map())) -> map().
update(Value, Key, Fun) -> Value#{Key := Fun(maps:get(Key, Value))}.

%% Publish the synthetic JSON receipt used by one validation attempt.
-spec write_receipt(file:filename(), map()) -> ok.
write_receipt(Root, Receipt) ->
    file:write_file(filename:join(Root, "compiled.json"), json:encode(Receipt)).

%% Reproduce the compact sorted-key JSON identity used by the build executor.
-spec identity(term()) -> binary().
identity(Value) -> hash(iolist_to_binary(json:encode(Value))).

%% Identify exact fixture bytes with lowercase SHA-256 text.
-spec hash(binary()) -> binary().
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

%% Isolate every receipt fixture in a fresh bounded build directory.
-spec with_directory(fun((file:filename()) -> term())) -> ok.
with_directory(Fun) ->
    Root = filename:absname(
        filename:join([
            "_build", "source-receipt-tests", integer_to_list(erlang:unique_integer([positive]))
        ])
    ),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    try
        _ = Fun(Root),
        ok
    after
        ok = file:del_dir_r(Root)
    end.
