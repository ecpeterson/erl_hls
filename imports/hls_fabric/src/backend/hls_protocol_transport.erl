-module(hls_protocol_transport).
-moduledoc "Builds source-bound publication, sender-local capture hardware and standalone actor receivers from fresh compilation. Whole-application connections and progress admission remain separate.".
-export([prepare/1, bundle/1, descriptor/1, plan/1, plan/2, emit/2, write/2]).
-export_type([program/0, build/0]).

%% Source-wide facts are shared by every placement; role selection never recompiles them.
-record(program, {bundle :: map(), capture :: map(), transactions :: map(),
    sources :: map(), inbox :: map(), fabric :: map(), ingress :: none | map(),
    model :: none | hls_protocol_model:report()}).
%% Emission retains the exact actor artifacts whose manifests enter the transport plan.
-record(build, {transport :: map(), files :: [actor_file()]}).
%% One relative actor path and its complete source-derived artifact.
-type actor_file() :: #{file := binary(), artifact := hls_local_actor:artifact()}.

-doc "One checked source program from prepare/1, shared across placements within a build. Contains source artifacts and topology, not an output directory or hardware admission. Keep it in process and do not edit it or reload its source modules while deriving roles; it is not a saved-plan input format.".
-opaque program() :: #program{}.

-doc "A checked transport placement from plan/1 or plan/2, with receiver artifacts ready for emission. Retain it unchanged in process; it grants no capacity, progress or device admission.".
-opaque build() :: #build{}.

-doc "Prepares, plans and emits a fresh source transport. See prepare/1 for source/configuration requirements and plan/2 for placement options. Returns the emitted transport descriptor; partial I/O failures are retained.".
-spec write(map(), file:filename()) -> map().
write(Config, Output) ->
    emit(plan(Config), Output).

-doc "Compiles the trusted sources list of {file, compiler options} pairs, invokes topology {module, function, arguments}, and elaborates within actor_limit. Checks direct/buffered routes, source-derived captures, publishers, startup and optional rectangle ingress. Optional protocol_model => {Module, Options} invokes an application-owned hls_protocol_model provider on the fresh inventory. Its checked graph establishes neither source refinement nor progress admission. Does not create output files. Loads declared source modules into the VM; constructors are trusted build code and may themselves have effects. Capture analysis independently reads producer source and must agree with the ordinary actor compilation.".
-spec prepare(map()) -> program().
prepare(Config = #{sources := Sources, topology := {Module, Function, Arguments}, actor_limit := Limit}) ->
    Loaded = [load(File, Options) || {File, Options} <- Sources],
    case length(Loaded) =:= length(lists:usort(Loaded)) of
        true -> ok; false -> error(duplicate_transport_source)
    end,
    true = lists:member(Module, Loaded),
    Normal = hls_topology:normalize(apply(Module, Function, Arguments)),
    Topology = #{actors := Actors, routes := Routes} = hls_protocol_topology:elaborate(Normal, Limit),
    lists:foreach(fun delivery/1, Routes),
    Used = lists:usort([M || #{module := M} <- Actors]),
    true = lists:all(fun(M) -> lists:member(M, Loaded) end, Used),
    Modules = maps:from_list([{M, compile(M)} || M <- Used]),
    Inventory = hls_protocol_inventory:inspect(Topology, Modules),
    [] = maps:get(diagnostics, Inventory),
    Model = hls_protocol_model:check(maps:get(protocol_model, Config, none), Inventory),
    Bundle = #{topology => Topology, modules => Modules, inventory => Inventory},
    Files = maps:from_list([{Id, source(maps:get(M, Modules))} || #{id := Id, module := M} <- Actors]),
    Capture = hls_protocol_capture:plan(Inventory, Files),
    %% The second source read must agree with the ordinary snapshot decoder's compilation.
    maps:foreach(fun(Id, Provenance) ->
        [#{module := M}] = [A || A = #{id := I} <- Actors, I =:= Id],
        #{plan := Plan} = maps:get(M, Modules),
        Provenance = xls_statem_plan:manifest(Plan)
    end, maps:get(sources, Capture)),
    Entries = maps:from_list([{Id, alternatives(maps:get(spec, maps:get(M, Modules)))}
        || #{id := Id, module := M} <- Actors]),
    Transactions = hls_protocol_transactions:plan(Inventory, Entries),
    Publishers = hls_protocol_source:plan(Bundle, Transactions, Capture),
    %% State invariants are outside this build boundary; literal source projections need none.
    true = lists:all(fun(#{constant_requirements := Requirements}) -> Requirements =:= [] end,
        [R || #{outputs := Outputs} <- maps:get(sources, Publishers), #{rows := Rows} <- Outputs, R <- Rows]),
    Inbox = hls_protocol_inbox:plan(Capture),
    #program{bundle = Bundle, capture = Capture, transactions = Transactions,
        sources = Publishers, inbox = Inbox, fabric = hls_protocol_fabric:plan(Publishers, Inbox),
        ingress = hls_protocol_ingress:plan(Bundle), model = Model}.

-doc "Returns the source bundle for downstream placement and host-codec binding. Treat it as read-only and retain the program's source modules; this accessor does not validate supplied bundles.".
-spec bundle(program()) -> map().
bundle(#program{bundle = Bundle}) -> Bundle.

-doc "Prepares one source program and plans its transport without creating output files. Accepts prepare/1 configuration plus plan/2's native_actors and arithmetic_groups options.".
-spec plan(map()) -> build().
plan(Config) ->
    plan(prepare(Config), maps:with([native_actors, arithmetic_groups], Config)).

-doc "Derives a placement from one unchanged source program without source reads or file writes. Options accepts only native_actors and arithmetic_groups. Omitted native_actors selects all actors; otherwise require a nonempty proper subset of unique logical IDs. Groups select disjoint source-compatible scalar completions, local by default. Builds source-bound receiver artifacts before emission, retaining global indices and canonical crossing ports. These ports still require ordered delivery, common clock/reset and stable offers; no framing or independent reset protocol is added here.".
-spec plan(program(), map()) -> build().
plan(#program{bundle = Bundle = #{topology := Topology = #{actors := Actors}, modules := Modules},
        capture = Capture, transactions = Transactions, sources = Publishers, inbox = Inbox,
        fabric = WholeFabric, ingress = WholeIngress, model = Model}, Options) ->
    case maps:keys(maps:without([native_actors, arithmetic_groups], Options)) of
        [] -> ok;
        Unknown -> error({unsupported_transport_options, lists:sort(Unknown)})
    end,
    #{fabric := Fabric, ingress := Ingress, indices := Native} = hls_protocol_partition:plan(
        Options, Bundle, Capture, WholeFabric, WholeIngress),
    Arithmetic = hls_protocol_arithmetic:plan(maps:get(arithmetic_groups, Options, []), Bundle, Native),
    Used = lists:sort(maps:keys(Modules)),
    ActorFunctions = [begin
        Relative = filename:join("actors", "actor_" ++ integer_to_list(I) ++ ".x"),
        Artifact = maps:get(M, Modules),
        #{module => M, file => list_to_binary(Relative), manifest => hls_local_actor:manifest(Artifact), artifact => Artifact}
    end || {I, M} <- lists:enumerate(0, Used)],
    Receivers = [begin
        Incoming = [L || L = #{destination_index := D} <- maps:get(links, Fabric), D =:= I],
        Messages = lists:append([Ms || #{target := Target, messages := Ms} <- maps:get(startup,Topology), Target =:= Id]),
        Owner = hls_protocol_arithmetic:receiver(I, Arithmetic, maps:get(M, Modules)),
        Artifact = hls_protocol_inbox:attach(Owner, Incoming, Capture, Messages, hls_protocol_ingress:addressed(Ingress,I)),
        Relative = filename:join("actors", "receiver_" ++ integer_to_list(I) ++ ".x"),
        #{index => I, module => M, file => list_to_binary(Relative), manifest => hls_local_actor:manifest(Artifact), artifact => Artifact}
    end || {I, #{id := Id, module := M}} <- lists:enumerate(0, Actors), lists:member(I, Native)],
    Files = [maps:with([file, artifact], A) || A <- ActorFunctions ++ Receivers],
    Transport = #{arithmetic => Arithmetic, bundle => Bundle, capture => Capture, transactions => Transactions,
        sources => Publishers, inbox => Inbox, fabric => Fabric, ingress => Ingress,
        actor_functions => [maps:remove(artifact, A) || A <- ActorFunctions],
        receivers => [maps:remove(artifact, R) || R <- Receivers]},
    Plan = case Model of none -> Transport; _ -> Transport#{protocol_model => Model} end,
    #build{transport = Plan, files = Files}.

-doc "Returns the checked transport descriptor before or after emission. Treat it as read-only; it describes the exact artifacts in Build and is also saved as transport.etf.".
-spec descriptor(build()) -> map().
descriptor(#build{transport = Transport}) -> Transport.

-doc "Emits a planned transport and its actor artifacts to a fresh directory without rereading source. Returns the transport descriptor also saved as transport.etf. The in-memory build is authoritative; saved output is for inspection and downstream consumers, not feedback into compilation. I/O failures retain partial output.".
-spec emit(build(), file:filename()) -> map().
emit(#build{transport = Plan = #{bundle := #{modules := Modules}, fabric := Fabric,
        actor_functions := ActorFunctions, receivers := Receivers}, files = Files}, Output) ->
    ok = file:make_dir(Output),
    ok = file:make_dir(filename:join(Output, "actors")),
    lists:foreach(fun(#{file := Relative, artifact := Artifact}) ->
        _ = hls_local_actor:write(Artifact, filename:join(Output, binary_to_list(Relative)))
    end, Files),
    ok = xls_protocol_transport:write(Fabric, filename:join(Output, "dslx")),
    ok = hls_protocol_model:write(maps:get(protocol_model, Plan, none), Output),
    ok = file:write_file(filename:join(Output, "transport.etf"), term_to_binary(Plan, [deterministic]), [exclusive]),
    Summary = #{actors => length(Receivers), links => length(maps:get(links, Fabric)),
        source_modules => lists:sort(maps:keys(Modules)), top => protocol_fabric, eligible => false,
        source_plans => maps:map(fun(_, #{plan := P}) -> maps:with([source_sha256, artifact_sha256, planner_md5], xls_statem_plan:manifest(P)) end, Modules),
        actor_functions => ActorFunctions, receivers => Receivers, actor_runtime => false, hardware => dslx, rtl => []},
    ok = file:write_file(filename:join(Output, "summary.json"), json:encode(Summary), [exclusive]),
    Plan.

%% Load only declared current source; no historical backend overlay enters the code path.
-spec load(file:filename(), list()) -> module().
load(File, Options) ->
    {ok, M, Bytes} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
    {module, M} = code:load_binary(M, File, Bytes), M.

%% The parse transform's context retains includes and preprocessing options.
-spec compile(module()) -> map().
compile(Module) ->
    [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
    Artifact = hls_local_actor:compile(maps:get(source_name, Context), Context),
    Artifact#{context => Context}.

%% Capture planning independently recompiles the same complete producer source.
-spec source(map()) -> map().
source(#{context := Context}) -> #{file => maps:get(source_name, Context), options => Context}.

%% Original storage fields retain slices and offsets for every send alternative.
-spec alternatives(map()) -> [map()].
alternatives(#{entries := Entries}) ->
    [Effect#{phase => Phase, layout => Layout, order => Order}
        || #{layouts := Layouts} <- Entries,
           #{phase := Phase, layout := Layout, storage := #{effects := Effects}} <- Layouts,
           {Order, Effect} <- lists:enumerate(0, Effects)].

%% Independent destination acceptance implements direct and buffered delivery only.
-spec delivery(map()) -> ok.
delivery(#{delivery := Mode}) when Mode =:= direct; Mode =:= buffered -> ok;
delivery(#{source := Source, delivery := Mode}) -> error({unsupported_transport_delivery, Source, Mode}).
