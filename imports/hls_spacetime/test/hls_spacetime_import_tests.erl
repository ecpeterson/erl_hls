-module(hls_spacetime_import_tests).
-include_lib("eunit/include/eunit.hrl").

%% The native-shaped fixture tests a parser contract, not a real Vivado measurement.
-spec native_import_test() -> ok.
native_import_test() ->
    with_export(fun(Directory)->
        P=hls_spacetime_import:read(Directory,build(),<<"checkpoint-digest">>),
        #{cells:=Cells,native:=#{paths:=[Path],net_delays:=[Delay]}}=P,
        [Constant]=[C||C=#{placement:=unplaced}<-Cells],
        ?assertMatch(#{x:=null,y:=null,site:=null,bel:=null},Constant),
        ?assertEqual(-0.2,maps:get(slack_ns,Path)),
        ?assertEqual(20,maps:get(fast_min_ps,Delay)),
        [Register]=[C||C=#{id:=<<"r0">>}<-Cells],
        ?assertEqual(<<"line\tbreak\nquote\\">>,maps:get(<<"NOTE">>,maps:get(properties,Register)))
    end).

%% Caller-supplied identities must agree with the exact exported build/checkpoint labels.
-spec identity_rejection_test() -> ok.
identity_rejection_test() ->
    with_export(fun(D)->
        ?assertError({spacetime_import,build_mismatch},hls_spacetime_import:read(D,(build())#{rtl:=<<"other">>},<<"checkpoint-digest">>)),
        ?assertError({spacetime_import,checkpoint_mismatch},hls_spacetime_import:read(D,build(),<<"other">>))
    end).

%% A final manifest cannot hide missing rows, wrong byte counts or an incomplete native export.
-spec coverage_rejection_test_() -> [term()].
coverage_rejection_test_() ->
    [?_test(with_export(fun(D)->
        modify_manifest(D,Change),
        ?assertException(error,{spacetime_import,_},hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>))
    end))||Change<-[
        fun(M)->maps:remove(<<"net_delay_basis">>,M) end,
        fun(M)->M#{<<"complete">>:=false} end,
        fun(M)->M#{<<"records">>:=0} end,
        fun(M)->M#{<<"bytes">>:=0} end,
        fun(M=#{<<"counts">>:=C})->M#{<<"counts">>:=C#{<<"cell_property_pairs">>:=0}} end,
        fun(M=#{<<"counts">>:=C})->M#{<<"counts">>:=C#{<<"delay_property_pairs">>:=0}} end,
        fun(M=#{<<"tables">>:=T})->M#{<<"tables">>:=maps:remove(<<"pins.tsv">>,T)} end,
        fun(M=#{<<"reports">>:=R})->M#{<<"reports">>:=maps:remove(<<"timing-min.rpt">>,R)} end
    ]].

%% A required SDF corner cannot be substituted, omitted or detached from its declared bytes.
-spec sdf_identity_rejection_test_() -> [term()].
sdf_identity_rejection_test_() ->
    [?_test(with_export(fun(D)->
        modify_manifest(D,Change),
        ?assertException(error,_,hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>))
    end))||Change<-[
        fun(M)->maps:remove(<<"sdf">>,M) end,
        fun(M=#{<<"sdf">>:=S})->M#{<<"sdf">>:=maps:remove(<<"fast">>,S)} end,
        fun(M=#{<<"sdf">>:=S=#{<<"fast">>:=F}})->M#{<<"sdf">>:=S#{<<"fast">>:=F#{<<"sha256">>:=binary:copy(<<"0">>,64)}}} end,
        fun(M=#{<<"sdf">>:=S=#{<<"fast">>:=F}})->M#{<<"sdf">>:=S#{<<"fast">>:=F#{<<"file">>:=<<"../other.sdf">>}}} end,
        fun(M=#{<<"sdf">>:=S=#{<<"fast">>:=F}})->M#{<<"sdf">>:=S#{<<"fast">>:=F#{<<"mode">>:=<<"timesim">>}}} end
    ]].

%% Compact maps reject duplicate JSON keys, non-string values and missing/duplicate object rows.
-spec property_rejections_test_() -> [term()].
property_rejections_test_() ->
    [?_test(with_export(fun(D)->
        replace_table(D,File,From,To),
        ?assertException(error,{spacetime_import,_},hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>))
    end))||{File,From,To}<-[
        {"cell-properties.tsv",<<"r1\t{}">>,<<"r1\t{\"K\":\"a\",\"K\":\"b\"}">>},
        {"cell-properties.tsv",<<"r1\t{}">>,<<"r1\t{\"K\":1}">>},
        {"cell-properties.tsv",<<"r1\t{}">>,<<"r1\t{\"K\":{}}">>},
        {"cell-properties.tsv",<<"r1\t{}">>,<<"r1\t[]">>},
        {"cell-properties.tsv",<<"r1\t{}\n">>,<<"r1\t{}\nr1\t{}\n">>},
        {"cell-properties.tsv",<<"r1\t{}\n">>,<<>>},
        {"cell-properties.tsv",<<"r1\t{}">>,<<"missing\t{}">>},
        {"delay-properties.tsv",<<"{\"TO_PIN\":\"r1/D\"}">>,<<"{\"TO_PIN\":\"a\",\"TO_PIN\":\"b\"}">>},
        {"delay-properties.tsv",<<"n0\td0\t{\"TO_PIN\":\"r1/D\"}\n">>,<<>>}
    ]].

%% Table references are checked even if every producer counter has been adjusted consistently.
-spec unknown_cell_test() -> ok.
unknown_cell_test() ->
    with_export(fun(D)->
        replace_table(D,"pins.tsv",<<"r0/Q\tr0\tQ">>,<<"r0/Q\tmissing\tQ">>),
        ?assertError({spacetime,{unknown_physical_reference,cell,<<"missing">>}},
            hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>))
    end).

%% A primitive pin cannot occupy two canonical nets under different native names or directions.
-spec duplicate_primitive_pin_test() -> ok.
duplicate_primitive_pin_test() ->
    with_export(fun(D) ->
        P = hls_spacetime_import:read(D, build(), <<"checkpoint-digest">>),
        %% r1/D is already an input on n0; another spelling cannot make it n1's output.
        Duplicate = #{cell => <<"r1">>, pin => <<"D">>, direction => output,
            native => <<"different_native_name/D">>},
        Nets = [case Net of
            #{id := <<"n1">>, pins := Pins} -> Net#{pins := Pins ++ [Duplicate]};
            _ -> Net
        end || Net <- maps:get(nets, P)],
        ?assertError({spacetime, {duplicate_physical_pin, <<"r1">>, <<"D">>}},
            hls_spacetime_physical:validate(build(), #{}, P#{nets := Nets}))
    end).

%% Missing timing values are explicit null; a malformed numeric token cannot become zero.
-spec invalid_timing_test() -> ok.
invalid_timing_test() ->
    with_export(fun(D)->
        replace_table(D,"net-delays.tsv",<<"\t20\t30\t40\t50">>,<<"\tN/A\t30\t40\t50">>),
        ?assertError({spacetime_import,{number,<<"N/A">>}},hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>))
    end).

%% A split encoded word is distributed, not replicated; every bit endpoint needs evidence.
-spec distributed_word_test() -> ok.
distributed_word_test() ->
    with_export(fun(D)->
        P=hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        Resources=#{<<"word">>=>#{width=>2}},
        Qualified=P#{generated=>[#{id=><<"word-rtl">>,source=><<"Two-bit generated register">>}],
            bindings=>[binding()]},
        ?assertMatch(#{mapped:=1,physical_cells:=3},hls_spacetime_physical:validate(build(),Resources,Qualified)),
        Absent=Qualified#{bindings=>[maps:remove(bits,binding())]},
        ?assertError({spacetime,missing_distributed_bits},hls_spacetime_physical:validate(build(),Resources,Absent)),
        Bad=Qualified#{bindings=>[(binding())#{bits:=[]} ]},
        ?assertError({spacetime,bit_binding_coverage},hls_spacetime_physical:validate(build(),Resources,Bad)),
        [B0,B1]=maps:get(bits,binding()),
        Unknown=Qualified#{bindings=>[(binding())#{bits:=[B0,maps:without([cell,pin],B1#{status:=unknown})]}]},
        ?assertError({spacetime,unsupported_distributed_bit},hls_spacetime_physical:validate(build(),Resources,Unknown)),
        WrongPin=Qualified#{bindings=>[(binding())#{bits:=[B0,B1#{pin:=<<"D">>}]}]},
        ?assertError({spacetime,{bit_output_pin,<<"r1">>,<<"D">>}},hls_spacetime_physical:validate(build(),Resources,WrongPin))
    end).

%% Names-only physical candidates may be retained, but cannot inflate mapped coverage.
-spec ambiguous_bits_test() -> ok.
ambiguous_bits_test() ->
    with_export(fun(D)->
        P=hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        [B0,B1]=maps:get(bits,binding()),
        B=(binding())#{disposition:=ambiguous,bits:=[B0,maps:without([cell,pin],B1#{status:=unknown})]},
        Q=P#{generated=>[#{id=><<"word-rtl">>,source=><<"Candidate only">>}],bindings=>[B]},
        ?assertMatch(#{mapped:=0,ambiguous:=1},hls_spacetime_physical:validate(build(),#{<<"word">>=>#{width=>2}},Q))
    end).

%% Native timing references and corner order are independent of parser byte-count consistency.
-spec native_rejections_test_() -> [term()].
native_rejections_test_() ->
    [?_test(with_export(fun(D)->
        P=hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        Q=P#{native:=Change(maps:get(native,P))},
        ?assertException(error,{spacetime,_},hls_spacetime_physical:validate(build(),#{},Q))
    end))||Change<-[
        fun(N)->N#{sampled_nets:=[<<"missing">>]} end,
        fun(N)->N#{sampled_nets:=[<<"n0">>,<<"n0">>]} end,
        fun(N)->N#{sampled_nets:=[]} end,
        fun(N)->maps:remove(net_delay_basis,N) end,
        fun(N)->N#{net_delay_basis:=<<"unspecified">>} end,
        fun(N=#{net_delays:=[V]})->N#{net_delays:=[V#{fast_min_ps:=31}]} end,
        fun(N=#{paths:=[V]})->N#{paths:=[V#{datapath_ns:=-1}]} end,
        fun(N=#{paths:=[V]})->N#{paths:=[V#{startpoint:=<<"missing/Q">>}]} end,
        fun(N=#{paths:=[V]})->N#{paths:=[V#{endpoint:=<<"missing/D">>}]} end,
        fun(N=#{paths:=[V]})->N#{paths:=[V#{members:=[#{kind=><<"cell">>,name=><<"missing">>}]}]} end,
        fun(N=#{aliases:=A})->N#{aliases:=A++A} end,
        fun(N)->N#{net_annotations:=[]} end,
        fun(N)->N#{net_delays:=[]} end
    ]].

%% Both native query bases survive import unchanged; neither silently rescales delay corners.
-spec net_delay_basis_test_() -> [term()].
net_delay_basis_test_() ->
    [?_test(with_export(fun(D)->
        modify_manifest(D,fun(M)->M#{<<"net_delay_basis">>:=Basis} end),
        #{native:=#{net_delay_basis:=Basis,net_delays:=[Delay]}} =
            hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        ?assertMatch(#{fast_min_ps:=20,slow_max_ps:=50},Delay)
    end))||Basis<-[<<"interconnect_only">>,<<"including_intrasite">>]].

%% Top-level ports are valid timing endpoints without being invented primitive pins.
-spec port_endpoint_test() -> ok.
port_endpoint_test() ->
    with_export(fun(D)->
        P=hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        #{native:=N=#{paths:=[V]}}=P,
        Q=P#{native:=N#{paths:=[V#{endpoint:=<<"out">>}]}},
        ?assertMatch(#{physical_cells:=3},hls_spacetime_physical:validate(build(),#{},Q))
    end).

%% Empty claims leave every semantic resource explicitly unmapped, without changing event histories.
-spec attach_unmapped_test() -> ok.
attach_unmapped_test() ->
    with_export(fun(D)->
        {ok,[B0]}=file:consult("test_data/spacetime_example.term"),
        B=B0#{build:=build(),evidence:=simulation_witness,physical:=null},
        P=hls_spacetime_import:read(D,build(),<<"checkpoint-digest">>),
        Joined=hls_spacetime_import:attach(B,P,#{generated=>[],bindings=>[]}),
        ?assertEqual(maps:remove(physical,B),maps:remove(physical,Joined)),
        ?assertMatch(#{mapping:=#{mapped:=0,unmapped:=5,physical_cells:=3}},hls_spacetime:validate(Joined))
    end).

%% Fixture correspondence is synthetic and supplied explicitly to test cardinality/ref checks.
-spec binding() -> map().
binding()->#{resource=><<"word">>,generated=>[<<"word-rtl">>],cells=>[<<"r0">>,<<"r1">>],
    disposition=>distributed,evidence=><<"Synthetic two-bit endpoint qualification">>,
    bits=>[#{bit=>0,status=>supported,cell=><<"r0">>,pin=><<"Q">>,evidence=><<"Synthetic bit0">>},
           #{bit=>1,status=>supported,cell=><<"r1">>,pin=><<"Q">>,evidence=><<"Synthetic bit1">>}]}.

%% Human-readable labels identify this parser fixture, never a native checkpoint.
-spec build() -> hls_spacetime:build().
build()->#{source=><<"fixture-source">>,rtl=><<"fixture-rtl">>,observation=><<"fixture-observer">>}.

%% Test-owned temporary files are always removed, including failed deliberate corruptions.
-spec with_export(fun((file:filename())->term())) -> ok.
with_export(Fun)->
    D=filename:join("/tmp","spacetime-import-"++integer_to_list(erlang:unique_integer([positive,monotonic]))),
    ok=file:make_dir(D),
    try
        lists:foreach(fun({N,T})->ok=file:write_file(filename:join(D,N),T,[exclusive]) end,fixture_tables()),
        ok=file:write_file(filename:join(D,"timing-max.rpt"),<<"synthetic max report\n">>,[exclusive]),
        ok=file:write_file(filename:join(D,"timing-min.rpt"),<<"synthetic min report\n">>,[exclusive]),
        lists:foreach(fun(Corner)->ok=file:write_file(filename:join(D,"timing-"++Corner++".sdf"),fixture_sdf(),[exclusive]) end,["fast","slow"]),
        write_manifest(D),Fun(D),ok
    after {ok,Names}=file:list_dir(D),lists:foreach(fun(N)->ok=file:delete(filename:join(D,N)) end,Names),ok=file:del_dir(D) end.

%% Synthetic SDF retains units, an interconnect arc and a conditional cell arc without inventing timing.
-spec fixture_sdf() -> binary().
fixture_sdf() ->
    <<"(DELAYFILE (SDFVERSION \"3.0\") (DESIGN \"fixture\") (DIVIDER /) (TIMESCALE 1ps)\n",
      "(CELL (CELLTYPE \"fixture\") (INSTANCE) (DELAY (ABSOLUTE (INTERCONNECT r0/Q r1/D (20:30:40) (21:31:41)))))\n",
      "(CELL (CELLTYPE \"FDRE\") (INSTANCE r0) (DELAY (ABSOLUTE (COND CE (IOPATH C Q (1:2:3) (2:3:4))))))\n",
      "(CELL (CELLTYPE \"FDRE\") (INSTANCE r1)))\n">>.

%% Compact tables exercise unplaced constants, output-pin mapping, aliases and static ps/ns fields.
-spec fixture_tables() -> [{string(),binary()}].
fixture_tables()->[
    {"cells.tsv",<<"name\tref\tsite\tbel\ttile\tx\ty\tclock_region\tplacement\nr0\tFDRE\tSLICE_X0Y0\tAFF\tCLB_X0Y0\t0\t0\tX0Y0\tplaced\nr1\tFDRE\tSLICE_X0Y0\tBFF\tCLB_X0Y0\t0\t0\tX0Y0\tplaced\nvcc\tVCC\t\t\t\t\t\t\tunplaced\n">>},
    {"cell-properties.tsv",iolist_to_binary([<<"cell\tproperties\n">>,
        property_row([<<"r0">>],#{<<"NOTE">>=><<"line\tbreak\nquote\\">>}),
        property_row([<<"r1">>],#{}),property_row([<<"vcc">>],#{})])},
    {"nets.tsv",<<"name\troute_status\ttype\tflat_pin_count\ttiming_status\nn0\tROUTED\tSIGNAL\t2\tavailable\nn1\tROUTED\tSIGNAL\t1\tempty\nnv\tGLOBAL\tPOWER\t1\tempty\n">>},
    {"aliases.tsv",<<"name\tcanonical\nn0\tn0\nn1\tn1\nnv\tnv\nlegacy/n0\tn0\n">>},
    {"pins.tsv",<<"net\tpin\tcell\tref_pin\tdirection\nn0\tr0/Q\tr0\tQ\tOUT\nn0\tr1/D\tr1\tD\tIN\nn1\tr1/Q\tr1\tQ\tOUT\nnv\tvcc/P\tvcc\tP\tOUT\n">>},
    {"ports.tsv",<<"net\tport\tdirection\nn0\tout\tOUT\n">>},
    {"net-delays.tsv",<<"net\tdelay\tfast_min_ps\tfast_max_ps\tslow_min_ps\tslow_max_ps\nn0\td0\t20\t30\t40\t50\n">>},
    {"delay-properties.tsv",iolist_to_binary([<<"net\tdelay\tproperties\n">>,
        property_row([<<"n0">>,<<"d0">>],#{<<"TO_PIN">>=><<"r1/D">>})])},
    {"paths.tsv",<<"id\tdelay_type\tstartpoint\tendpoint\tstart_clock\tend_clock\tslack_ns\tdatapath_ns\trequirement_ns\tlogic_levels\np0\tmax\tr0/Q\tr1/D\tclk\tclk\t-0.2\t1.2\t1.0\t0\n">>},
    {"path-properties.tsv",<<"path\tproperty\tvalue\np0\tSLACK\t-0.2\n">>},
    {"path-members.tsv",<<"path\tkind\tname\np0\tcell\tr0\np0\tcell\tr1\np0\tnet\tn0\np0\tpin\tr0/Q\np0\tpin\tr1/D\n">>},
    {"issues.tsv",<<"stage\tobject\treason\n">>}
].

%% JSON property text is escaped once more for the surrounding TSV wire format.
-spec property_row([binary()],map()) -> iodata().
property_row(Columns,Properties) ->
    [lists:join(<<"\t">>,Columns++[tsv_escape(iolist_to_binary(json:encode(Properties)))]),<<"\n">>].

%% Escape backslashes before introducing the table's tab/newline escape sequences.
-spec tsv_escape(binary()) -> binary().
tsv_escape(B) ->
    lists:foldl(fun({From,To},Acc)->binary:replace(Acc,From,To,[global]) end,B,
        [{<<"\\">>,<<"\\\\">>},{<<"\t">>,<<"\\t">>},{<<"\n">>,<<"\\n">>},{<<"\r">>,<<"\\r">>}]).

%% Counters reflect actual fixture bytes; corruption tests mutate one evidence obligation separately.
-spec write_manifest(file:filename()) -> ok.
write_manifest(D)->
    Tables=maps:from_list([begin {ok,B}=file:read_file(filename:join(D,N)),
        {list_to_binary(N),#{<<"rows">>=>length(binary:split(B,<<"\n">>,[global]))-2,<<"bytes">>=>byte_size(B)}}
        end||{N,_}<-fixture_tables()]),
    Reports=maps:from_list([begin {ok,B}=file:read_file(filename:join(D,N)),{list_to_binary(N),#{<<"bytes">>=>byte_size(B)}} end||N<-["timing-max.rpt","timing-min.rpt"]]),
    Sdf=maps:from_list([begin
        Name="timing-"++Corner++".sdf",{ok,B}=file:read_file(filename:join(D,Name)),
        {list_to_binary(Corner),#{<<"file">>=>list_to_binary(Name),<<"bytes">>=>byte_size(B),
            <<"sha256">>=>binary:encode_hex(crypto:hash(sha256,B),lowercase),
            <<"process_corner">>=>list_to_binary(Corner),<<"mode">>=><<"sta">>}}
    end||Corner<-["fast","slow"]]),
    Manifest=#{<<"format">>=><<"spacetime_physical_export">>,<<"schema">>=>1,<<"complete">>=>true,
        <<"build">>=>#{<<"source">>=><<"fixture-source">>,<<"rtl">>=><<"fixture-rtl">>,<<"observation">>=><<"fixture-observer">>},
        <<"checkpoint">>=>#{<<"sha256">>=><<"checkpoint-digest">>,<<"file">>=><<"synthetic.dcp">>},
        <<"tool">>=><<"synthetic fixture, not Vivado">>,<<"part">>=><<"synthetic part">>,
        <<"net_delay_basis">>=><<"interconnect_only">>,
        <<"sampled_nets">>=>[<<"n0">>,<<"n1">>,<<"nv">>],
        <<"counts">>=>#{<<"cell_property_pairs">>=>1,<<"delay_property_pairs">>=>1},
        <<"tables">>=>Tables,<<"reports">>=>Reports,<<"sdf">>=>Sdf,
        <<"records">>=>lists:sum([maps:get(<<"rows">>,T)||T<-maps:values(Tables)]),
        <<"bytes">>=>lists:sum([maps:get(<<"bytes">>,T)||T<-maps:values(Tables)++maps:values(Reports)++maps:values(Sdf)])},
    file:write_file(filename:join(D,"manifest.json"),json:encode(Manifest)).

%% Change only the final manifest, leaving native data bytes intact.
-spec modify_manifest(file:filename(),fun((map())->map())) -> ok.
modify_manifest(D,Change)->
    P=filename:join(D,"manifest.json"),{ok,B}=file:read_file(P),file:write_file(P,json:encode(Change(json:decode(B)))).

%% Keep valid size/count metadata while testing a native semantic contradiction.
-spec replace_table(file:filename(),string(),binary(),binary()) -> ok.
replace_table(D,Name,From,To)->
    P=filename:join(D,Name),{ok,B}=file:read_file(P),
    ok=file:write_file(P,binary:replace(B,From,To,[global])),write_manifest(D).
