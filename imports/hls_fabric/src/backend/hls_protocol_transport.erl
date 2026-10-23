-module(hls_protocol_transport).
-moduledoc "Builds source-bound publication, sender-local capture hardware and standalone actor receivers from fresh compilation. Whole-application connections and progress admission remain separate.".
-export([write/2]).

-doc "Compiles the explicit trusted source list, invokes its topology constructor, checks and elaborates the topology, then emits complete ordinary actor functions, per-actor capture/startup receivers, and connected publisher/capture DSLX into a fresh directory. Accepts direct and independently buffered routes only. Config contains sources as {file, compiler options} pairs, topology as {module, function, arguments}, and actor_limit. Only complete ordinary source alternatives establish omitted constants; no supplied state facts or saved plans are accepted. Returns the complete transport plan. Each source port requires an evaluated ordinary entry snapshot; generated receivers supply destination eligibility, acquisition and release when wired to their matching links. Their ordinary effect outputs are not yet connected to source snapshots. Successful emission is not sufficient application capacity, progress, mailbox replacement or hardware admission. Source lists and constructors are trusted build code; partial outputs after I/O failure are retained.".
-spec write(map(), file:filename()) -> map().
write(#{sources := Sources, topology := {Module, Function, Arguments}, actor_limit := Limit}, Output) ->
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
    Fabric = hls_protocol_fabric:plan(Publishers, Inbox),
    ok = file:make_dir(Output),
    ActorDirectory = filename:join(Output, "actors"),
    ok = file:make_dir(ActorDirectory),
    ActorFunctions = [begin
        Relative = filename:join("actors", "actor_" ++ integer_to_list(I) ++ ".x"),
        Summary = hls_local_actor:write(maps:get(M, Modules), filename:join(Output, Relative)),
        #{module => M, file => list_to_binary(Relative), manifest => Summary}
    end || {I, M} <- lists:enumerate(0, Used)],
    Receivers = [begin
        Incoming = [L || L = #{destination_index := D} <- maps:get(links, Fabric), D =:= I],
        Messages = lists:append([Ms || #{target := Target, messages := Ms} <- maps:get(startup,Topology), Target =:= Id]),
        Artifact = hls_protocol_inbox:attach(maps:get(M, Modules), Incoming, Capture, Messages),
        Relative = filename:join("actors", "receiver_" ++ integer_to_list(I) ++ ".x"),
        Manifest = hls_local_actor:write(Artifact, filename:join(Output, Relative)),
        #{index => I, module => M, file => list_to_binary(Relative), manifest => Manifest}
    end || {I, #{id := Id, module := M}} <- lists:enumerate(0, Actors)],
    ok = xls_protocol_transport:write(Fabric, filename:join(Output, "dslx")),
    Plan = #{bundle => Bundle, capture => Capture, transactions => Transactions,
        sources => Publishers, inbox => Inbox, fabric => Fabric, actor_functions => ActorFunctions, receivers => Receivers},
    ok = file:write_file(filename:join(Output, "transport.etf"), term_to_binary(Plan, [deterministic]), [exclusive]),
    Summary = #{actors => length(Actors), links => length(maps:get(links, Fabric)),
        source_modules => Used, top => protocol_fabric, eligible => false,
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
