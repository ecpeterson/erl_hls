-module(xls_protocol_spacetime_workflow).
-include_lib("kernel/include/file.hrl").
-moduledoc "Packages passive source-protocol observers and converts their saved recordings. Planning reads exact build inputs; writing snapshots the simulator inputs and emits an explicit external build command. No compiler, simulator, native tool or application stimulus runs inside this API.".

%% Offline producer preparation and fresh artifact publication.
-export([prepare/1, write/2, read_plan/1, write_capture/3, write_qualification/5]).
-export_type([config/0, prepared/0]).

-doc "Trusted local source-build directory, raw/optimized boundary IR, boundary RTL and compiled files.f directory. Paths resolve from the caller; scope defaults to full. Explicit storage scope omits semantic attribution and retains unsupported-control diagnostics; unknown options reject. The compiled closure must contain the supplied boundary RTL bytes.".
-type config() :: #{
    source := file:filename_all(),
    raw_ir := file:filename_all(),
    optimized_ir := file:filename_all(),
    boundary_rtl := file:filename_all(),
    compiled := file:filename_all(),
    scope => full | storage
}.

-doc "Checked observation plan and exact simulator input bytes, retained until write/2. This trusted in-process value is not an external interchange or executable compilation plan.".
-opaque prepared() :: #{
    plan := xls_protocol_spacetime:plan(),
    files := #{binary() => binary()},
    rtl := [binary()],
    inputs := map()
}.

%% Public artifact boundaries have independent decoded-byte ceilings.
-define(MAX_INPUT, 268435456).
-define(MAX_PLAN, 16777216).
-define(MAX_FILES, 512).

-doc "Reads and checks one generated source-protocol build, resolves its observation plan and prepares the packaged passive harness. Source hashes and application actor count are checked by the planner; compiled RTL and support bytes are snapshotted. Rejects missing/unsafe file-list entries, duplicate paths, unsupported source bindings and more than 512 RTL files or 256 MiB total input. Executes no tools and creates no files.".
-spec prepare(config() | file:filename_all()) -> prepared().
prepare(Config) when is_map(Config) ->
    [] = maps:keys(Config) -- [boundary_rtl, compiled, optimized_ir, raw_ir, source, scope],
    #{
        source := Source,
        raw_ir := Raw,
        optimized_ir := Opt,
        boundary_rtl := Rtl,
        compiled := Compiled
    } = Config,
    FullPlan = xls_protocol_spacetime:plan(Source, Raw, Opt, Rtl),
    Plan = select_scope(FullPlan, maps:get(scope, Config, full)),
    Paths = file_list(Compiled),
    RtlFiles = rtl_files(Compiled, Paths, 0, []),
    RtlBytes = read(Rtl, ?MAX_INPUT),
    true = lists:any(fun({_, Bytes}) -> Bytes =:= RtlBytes end, RtlFiles),
    Actors = length(maps:get(actors, FullPlan)),
    Template = read(
        priv(hls_spacetime_observer, "simulator/protocol_spacetime_sim.cpp.in"), ?MAX_PLAN
    ),
    Harness = harness(Template, Actors),
    Files = maps:from_list(
        RtlFiles ++
            [
                {<<"simulation.cpp">>, Harness},
                {<<"framed_fifo_stream.h">>,
                    read(priv(hls_lowering, "simulator/framed_fifo_stream.h"), ?MAX_PLAN)},
                {<<"spacetime_trace.h">>,
                    read(priv(hls_spacetime, "include/spacetime_trace.h"), ?MAX_PLAN)},
                {<<"raw.ir">>, read(Raw, ?MAX_INPUT)},
                {<<"optimized.ir">>, read(Opt, ?MAX_INPUT)},
                {<<"source-build.json">>,
                    read(filename:join(Source, "source-build.json"), ?MAX_PLAN)}
            ]
    ),
    true = lists:sum([byte_size(B) || B <- maps:values(Files)]) =< ?MAX_INPUT,
    #{
        inputs := #{
            raw_ir := RawHash,
            optimized_ir := OptHash,
            rtl := RtlHash,
            source_build := SourceHash
        }
    } = Plan,
    RawHash = hash(maps:get(<<"raw.ir">>, Files)),
    OptHash = hash(maps:get(<<"optimized.ir">>, Files)),
    RtlHash = hash(RtlBytes),
    SourceHash = hash(maps:get(<<"source-build.json">>, Files)),
    ok = check_copied_rtl(maps:get(<<"source-build.json">>, Files), RtlFiles),
    #{
        plan => Plan,
        files => Files,
        rtl => [N || {N, _} <- RtlFiles],
        inputs => #{
            source => path(Source),
            raw_ir => path(Raw),
            optimized_ir => path(Opt),
            boundary_rtl => path(Rtl),
            compiled => path(Compiled)
        }
    };
prepare(Path) ->
    {ok, [Config]} = file:consult(Path),
    prepare(Config).

-doc "Writes a prepared observer into a fresh directory. Retains deterministic uncompressed observation.etf, taps.tsv, copied RTL/headers, source/IR identities and build-simulator.sh. The script takes one explicit Verilator executable and builds serially when the caller invokes it; this function executes nothing. A final manifest.json binds every input and command. I/O failure leaves an incomplete directory; existing output is never replaced.".
-spec write(prepared(), file:filename_all()) -> map().
write(#{plan := Plan, files := Inputs, rtl := Rtl, inputs := Origins}, Directory) ->
    PlanBytes = term_to_binary(Plan, [deterministic]),
    true = byte_size(PlanBytes) =< ?MAX_PLAN,
    Files = Inputs#{
        <<"observation.etf">> => PlanBytes,
        <<"taps.tsv">> => iolist_to_binary(xls_protocol_spacetime:tsv(Plan)),
        <<"build-simulator.sh">> => iolist_to_binary(build_script(Rtl))
    },
    Metadata = #{
        format => spacetime_observer_preparation,
        schema => 1,
        complete => true,
        build => build(Plan),
        inputs => Origins,
        observation_scope => maps:get(observation_scope, Plan, full),
        unavailable_semantics => maps:get(unavailable_semantics, Plan, []),
        limits => #{
            cycles => 4000000,
            records => 1000000,
            decoded_bytes => ?MAX_INPUT,
            simulator_seconds => 120,
            local_process_group_bytes => 6442450944
        },
        scope =>
            <<"Passive source-protocol recorder; external simulator execution and application stimulus remain caller-owned. Apply a process-group guard to compilation and capture.">>
    },
    write_directory(Directory, Files, Metadata).

-doc "Reads the deterministic uncompressed plan from a completed preparation after checking its manifest identity, declared size and SHA256. Accepts only trusted local output from write/2; it is not an arbitrary uploaded ETF boundary. Rejects compression, stale build identity and plans over 16 MiB. No source or scratch directory is reopened.".
-spec read_plan(file:filename_all()) -> xls_protocol_spacetime:plan().
read_plan(Directory) ->
    #{
        <<"format">> := <<"spacetime_observer_preparation">>,
        <<"schema">> := 1,
        <<"complete">> := true,
        <<"files">> := Files,
        <<"build">> := Build
    } =
        json:decode(read(filename:join(Directory, "manifest.json"), ?MAX_PLAN)),
    Bytes = verified(Directory, <<"observation.etf">>, Files, ?MAX_PLAN),
    <<131, Tag, _/binary>> = Bytes,
    true = Tag =/= 80,
    {Plan, Used} = binary_to_term(Bytes, [used]),
    Used = byte_size(Bytes),
    ok = data(Plan),
    Build = json:decode(iolist_to_binary(json:encode(build(Plan)))),
    Plan.

-doc "Interprets one saved trace using its completed preparation and writes a fresh capture directory. Outputs bundle.json, deterministic uncompressed bundle.etf, backend stream/publication/ancestry JSON sidecars, summary.json and a final byte/hash manifest. All output bytes together are capped at 256 MiB. Input trace must satisfy the bounded reader; an explicitly incomplete trace remains incomplete in the graph. Records input identities and exact observation digest. No simulator, native import, application decoding or physical claims run here.".
-spec write_capture(file:filename_all(), file:filename_all(), file:filename_all()) -> map().
write_capture(Prepared, TraceFile, Directory) ->
    PreparationFile = filename:join(Prepared, "manifest.json"),
    PreparationBytes = read(PreparationFile, ?MAX_PLAN),
    Plan = read_plan(Prepared),
    PreparationBytes = read(PreparationFile, ?MAX_PLAN),
    TraceBytes = read(TraceFile, ?MAX_INPUT),
    Trace = hls_spacetime_trace:read(TraceFile),
    %% Bind the bytes consumed by the reader; a changing source file cannot be published.
    TraceBytes = read(TraceFile, ?MAX_INPUT),
    #{bundle := Bundle} =
        Capture = xls_protocol_spacetime_capture:capture(Plan, Trace, build(Plan)),
    Sidecars = maps:from_list([
        {<<(atom_to_binary(K))/binary, ".json">>, iolist_to_binary(json:encode(V))}
     || {K, V} <- maps:to_list(maps:remove(bundle, Capture))
    ]),
    Summary = hls_spacetime:validate(Bundle),
    Files = Sidecars#{
        <<"bundle.json">> => iolist_to_binary(hls_spacetime:encode(Bundle)),
        <<"bundle.etf">> => term_to_binary(Bundle, [deterministic]),
        <<"summary.json">> => iolist_to_binary(json:encode(Summary))
    },
    true = lists:sum([byte_size(B) || B <- maps:values(Files)]) =< ?MAX_INPUT,
    Metadata = #{
        format => spacetime_observer_capture,
        schema => 1,
        complete => true,
        capture_complete => maps:get(complete, Trace),
        unit => cycle,
        build => build(Plan),
        observation_scope => maps:get(observation_scope, Plan, full),
        unavailable_semantics => maps:get(unavailable_semantics, Plan, []),
        inputs => #{
            trace => (identity(TraceBytes))#{path => path(TraceFile)},
            preparation_manifest => identity(PreparationBytes)
        },
        evidence => simulation_witness,
        scope =>
            <<"Recorded supported dependencies and register transfers; no native physical correspondence, all-input equivalence or execution period.">>
    },
    PreparationBytes = read(PreparationFile, ?MAX_PLAN),
    write_directory(Directory, Files, Metadata).

-doc "Reads a validated local catalogue/bundle and independently reviewed candidate/comparison terms, qualifies their stored-bit associations and writes claims.etf plus qualification.etf/JSON in a fresh directory. Files must be uncompressed trusted ETF at most 256 MiB each. Exact input bytes are inventoried; declared netlist/probe identities and comparison authenticity remain the caller's responsibility. No native tools, replay or candidate discovery runs here. Unknown bits stay unknown.".
-spec write_qualification(
    file:filename_all(),
    file:filename_all(),
    file:filename_all(),
    file:filename_all(),
    file:filename_all()
) -> map().
write_qualification(CatalogueFile, BundleFile, CandidatesFile, WitnessFile, Directory) ->
    lists:foreach(
        fun(Module) -> {module, Module} = code:ensure_loaded(Module) end,
        [
            xls_protocol_spacetime_physical,
            hls_spacetime,
            hls_spacetime_storage,
            hls_spacetime_physical,
            hls_spacetime_native,
            hls_spacetime_import,
            hls_spacetime_sdf
        ]
    ),
    Inputs = [
        {catalogue, CatalogueFile},
        {bundle, BundleFile},
        {candidates, CandidatesFile},
        {witness, WitnessFile}
    ],
    Read = [{Key, term_file(Path), Path} || {Key, Path} <- Inputs],
    Terms = maps:from_list([{K, Term} || {K, {Term, _}, _} <- Read]),
    #{catalogue := Catalogue, bundle := Bundle, candidates := Candidates, witness := Witness} =
        Terms,
    #{build := Build, resources := Resources} = Bundle,
    #{build := Build} = Catalogue,
    _ = hls_spacetime:validate(Bundle),
    _ = hls_spacetime_physical:validate(Build, #{}, Catalogue),
    Qualified = xls_protocol_spacetime_physical:qualify(Catalogue, Candidates, Witness),
    Claims = xls_protocol_spacetime_physical:claims(Resources, Qualified),
    _ = hls_spacetime_import:attach(Bundle, Catalogue, Claims),
    Files = #{
        <<"claims.etf">> => term_to_binary(Claims, [deterministic]),
        <<"qualification.etf">> => term_to_binary(Qualified, [deterministic]),
        <<"qualification.json">> => iolist_to_binary(json:encode(Qualified))
    },
    write_directory(Directory, Files, #{
        format => spacetime_physical_qualification,
        schema => 1,
        complete => true,
        build => Build,
        inputs => maps:from_list([
            {K, (identity(Bytes))#{path => path(Path)}}
         || {K, {_, Bytes}, Path} <- Read
        ]),
        scope =>
            <<"Native output-pin/net membership and independently reviewed finite value correspondence; no all-input equivalence, write proof or dynamic causality.">>
    }).

%% Safe decoding accepts only already known schema atoms; compressed payloads cannot bypass the cap.
-spec term_file(file:filename_all()) -> {term(), binary()}.
term_file(Path) ->
    Bytes = read(Path, ?MAX_INPUT),
    <<131, Tag, _/binary>> = Bytes,
    true = Tag =/= 80,
    {Term, Used} = binary_to_term(Bytes, [safe, used]),
    Used = byte_size(Bytes),
    ok = data(Term),
    {Term, Bytes}.

%% Artifact interchange contains ordinary data only, never executable/process values.
-spec data(term()) -> ok.
data(Term) when is_atom(Term); is_binary(Term); is_number(Term) -> ok;
data(Term) when is_list(Term) -> lists:foreach(fun data/1, Term);
data(Term) when is_tuple(Term) -> data(tuple_to_list(Term));
data(Term) when is_map(Term) ->
    maps:foreach(
        fun(K, V) ->
            data(K),
            data(V)
        end,
        Term
    );
data(_) ->
    error(spacetime_non_data_term).

%% Mechanical RTL copied by the external build must match the checked emitted source bytes.
-spec check_copied_rtl(binary(), [{binary(), binary()}]) -> ok.
check_copied_rtl(ManifestBytes, RtlFiles) ->
    #{<<"inputs">> := Inputs} = json:decode(ManifestBytes),
    Index = maps:from_list([{maps:get(<<"file">>, I), maps:get(<<"sha256">>, I)} || I <- Inputs]),
    lists:foreach(
        fun({<<"rtl/", Name/binary>>, Bytes}) ->
            case maps:find(Name, Index) of
                {ok, Expected} ->
                    Expected = hash(Bytes),
                    ok;
                error ->
                    ok
            end
        end,
        RtlFiles
    ).

%% A requested storage-only recording cannot silently acquire partial semantic claims.
-spec select_scope(xls_protocol_spacetime:plan(), full | storage) -> xls_protocol_spacetime:plan().
select_scope(Plan, full) ->
    [] = maps:get(unsupported, Plan),
    Plan;
select_scope(Plan, storage) ->
    Omitted = #{
        categories => [actor_actions, ownership, publications, scalar_ancestry, public_stream],
        unsupported_controls => maps:get(unsupported, Plan)
    },
    maps:without([stream, publication, dependencies], Plan#{
        actors := [],
        unsupported := [],
        observation_scope => storage,
        unavailable_semantics => Omitted
    }).

%% Build identities describe the exact observation domain, not a physical checkpoint.
-spec build(xls_protocol_spacetime:plan()) -> hls_observation_build:build().
build(Plan = #{inputs := #{source_build := Source, rtl := Rtl}}) ->
    hls_observation_build:new(Source, Rtl, xls_protocol_spacetime:observation_digest(Plan)).

%% Source fault aggregation follows the verified public wrapper's actor population.
-spec harness(binary(), non_neg_integer()) -> binary().
harness(Template, Actors) ->
    [_] = binary:matches(Template, <<"@@SOURCE_FAULTS@@">>),
    Faults =
        [<<"dut.ingress_fault">>] ++
            [
                iolist_to_binary(["dut.actor_", integer_to_binary(I), "_", Kind])
             || Kind <- ["failure", "fault"], I <- lists:seq(0, Actors - 1)
            ],
    Result = binary:replace(
        Template, <<"@@SOURCE_FAULTS@@">>, iolist_to_binary(lists:join(" || ", Faults))
    ),
    nomatch = binary:match(Result, <<"@@">>),
    Result.

%% Commands quote each emitted relative path; the caller supplies the executable directly.
-spec build_script([binary()]) -> iodata().
build_script(Rtl) ->
    [
        "#!/bin/sh\n# Generated passive recorder build; caller supplies outer resource guard.\nset -eu\n",
        "[ \"$#\" = 1 ] || { echo 'usage: build-simulator.sh VERILATOR_EXECUTABLE' >&2; exit 2; }\n",
        "base=$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)\n",
        "[ ! -e \"$base/obj_dir\" ] || { echo 'simulator output already exists' >&2; exit 2; }\n",
        "exec \"$1\" --cc --exe --build --vpi --public-flat-rw --top-module protocol_application_top \\\n",
        "  --Mdir \"$base/obj_dir\" -j 1 -Wno-fatal -CFLAGS '-std=c++17' -o simulation",
        [[" \\\n  \"$base/\"", shell_quote(N)] || N <- Rtl],
        " \\\n  \"$base/simulation.cpp\"\n"
    ].

%% Single-quote escaping is shell syntax, not JSON string escaping.
-spec shell_quote(binary()) -> iodata().
shell_quote(Bytes) -> ["'", binary:replace(Bytes, <<"'">>, <<"'\\''">>, [global]), "'"].

%% The compiled manifest lists literal relative filenames, not shell words or glob patterns.
-spec file_list(file:filename_all()) -> [binary()].
file_list(Directory) ->
    Lines = [
        string:trim(L)
     || L <- binary:split(read(filename:join(Directory, "files.f"), ?MAX_PLAN), <<"\n">>, [global])
    ],
    Paths = [L || L <- Lines, L =/= <<>>],
    true = Paths =/= [] andalso length(Paths) =< ?MAX_FILES,
    true = length(Paths) =:= length(lists:usort(Paths)),
    lists:foreach(fun relative/1, Paths),
    Paths.

%% Enforce the aggregate RTL budget before allocating the next input.
-spec rtl_files(file:filename_all(), [binary()], non_neg_integer(), [{binary(), binary()}]) ->
    [{binary(), binary()}].
rtl_files(_, [], _, Reverse) ->
    lists:reverse(Reverse);
rtl_files(Directory, [Name | Rest], Used, Reverse) ->
    true = Used < ?MAX_INPUT,
    Bytes = read(filename:join(Directory, Name), ?MAX_INPUT - Used),
    rtl_files(Directory, Rest, Used + byte_size(Bytes), [{<<"rtl/", Name/binary>>, Bytes} | Reverse]).

%% Prevent copied input paths escaping the owned preparation directory.
-spec relative(binary()) -> ok.
relative(Name) ->
    relative = filename:pathtype(Name),
    false = lists:member(<<"..">>, filename:split(Name)),
    nomatch = re:run(Name, <<"[\\x00-\\x1f\\x7f]">>, [{capture, none}]),
    ok.

%% Size is checked before reading; exact descriptor sizes are checked after reading too.
-spec read(file:filename_all(), pos_integer()) -> binary().
read(Path, Limit) ->
    {ok, #file_info{size = Size, type = regular}} = file:read_file_info(Path),
    true = is_integer(Size) andalso Size >= 0 andalso Size =< Limit,
    {ok, Bytes} = file:read_file(Path),
    true = byte_size(Bytes) =:= Size,
    Bytes.

%% A plan is never decoded before its retained file identity matches.
-spec verified(file:filename_all(), binary(), map(), pos_integer()) -> binary().
verified(Directory, Name, Files, Limit) ->
    Bytes = read(filename:join(Directory, Name), Limit),
    #{<<"bytes">> := Size, <<"sha256">> := Hash} = maps:get(Name, Files),
    Size = byte_size(Bytes),
    Hash = hash(Bytes),
    Bytes.

%% OTP priv ownership keeps installed workflows independent of repository test paths.
-spec priv(atom(), string()) -> file:filename_all().
priv(Application, Relative) ->
    case code:priv_dir(Application) of
        {error, Reason} -> error({spacetime_application_unavailable, Application, Reason});
        Directory -> filename:join(Directory, Relative)
    end.

%% Record paths for diagnostics only; bytes and content identities authorize interpretation.
-spec path(file:filename_all()) -> binary().
path(Path) -> unicode:characters_to_binary(filename:absname(Path)).

%% The completion marker is written last, after every bounded output is durable.
-spec write_directory(file:filename_all(), #{binary() => binary()}, map()) -> map().
write_directory(Directory, Files, Metadata) ->
    ok = file:make_dir(Directory),
    maps:foreach(
        fun(Name, Bytes) ->
            ok = relative(Name),
            Path = filename:join(Directory, Name),
            ok = filelib:ensure_dir(Path),
            ok = file:write_file(Path, Bytes, [exclusive])
        end,
        Files
    ),
    Manifest = Metadata#{files => maps:map(fun(_, Bytes) -> identity(Bytes) end, Files)},
    ok = file:write_file(filename:join(Directory, "manifest.json"), json:encode(Manifest), [
        exclusive
    ]),
    Manifest.

%% Literal file hashes stay separate from the semantic deterministic plan identity.
-spec identity(binary()) -> #{bytes := non_neg_integer(), sha256 := binary()}.
identity(Bytes) -> #{bytes => byte_size(Bytes), sha256 => hash(Bytes)}.

%% SHA256 never interns external file content as an Erlang atom.
-spec hash(binary()) -> binary().
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
