-module(hls_protocol_transport).
-moduledoc "Builds source-bound publication, sender-local capture hardware and standalone actor receivers from fresh compilation. Whole-application connections and progress admission remain separate.".
-export([prepare/1, bundle/1, control/1, descriptor/1, plan/1, plan/2, emit/1, write/2]).
-export_type([program/0, build/0, bundle/0, descriptor/0, actor_descriptor/0]).

-doc "One elaborated topology, its checked source snapshots and source inventory. Emission adds DSLX to module artifacts without changing these semantic bindings.".
-type bundle() :: #{topology := hls_protocol_topology:plan(),
    modules := #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    inventory := hls_protocol_inventory:report()}.

-doc "File ownership and source/receiver interface metadata, static during planning and finalized with a required DSLX hash after emission.".
-type actor_descriptor() :: #{module := module(), file := binary(), manifest := hls_local_actor:descriptor() | hls_local_actor:manifest(), index => non_neg_integer()}.

-doc "Checked placement, publication, capture and receiver interfaces. Before emission module snapshots contain no DSLX and manifests omit byte hashes; emit/1 returns the finalized descriptor with those artifacts and identities attached.".
-type descriptor() :: #{arithmetic := [hls_protocol_arithmetic:group()], bundle := bundle(),
    capture := hls_protocol_capture:plan(), transactions := hls_protocol_transactions:plan(),
    sources := hls_protocol_source:plan(), inbox := hls_protocol_inbox:plan(),
    fabric := hls_protocol_fabric:plan(), ingress := none | hls_protocol_control:plan(),
    whole_control := none | hls_protocol_control:plan(), actor_functions := [actor_descriptor()],
    receivers := [actor_descriptor()], protocol_model => hls_protocol_model:report()}.

%% Source-wide facts are shared by every placement; role selection never recompiles them.
-record(program, {bundle :: bundle(), capture :: hls_protocol_capture:plan(),
    transactions :: hls_protocol_transactions:plan(), sources :: hls_protocol_source:plan(),
    inbox :: hls_protocol_inbox:plan(), fabric :: hls_protocol_fabric:plan(),
    ingress :: none | hls_protocol_control:plan(), model :: none | hls_protocol_model:report()}).
%% Each receiver retains checked source ownership and inbox layout, never rendered text.
-record(receiver, {source :: hls_local_actor:source(), layout :: hls_protocol_inbox:layout()}).
%% Static descriptor and ordered receiver layouts are one trusted emission input.
-record(build, {transport :: descriptor(), receivers :: [#receiver{}]}).

-doc "One checked source program from prepare/1, shared across placements within a build. Contains source artifacts and topology, not an output directory or hardware admission. Keep it in process and do not edit it or reload its source modules while deriving roles; it is not a saved-plan input format.".
-opaque program() :: #program{}.

-doc "A checked transport placement from plan/1 or plan/2, with checked receiver layouts ready for rendering. Retain it unchanged in process; it grants no capacity, progress or device admission.".
-opaque build() :: #build{}.

-doc "Writes emit/1's generated files to a fresh directory and returns the transport descriptor. Accepts a trusted source config map or filename, or an unchanged in-process build. Generation finishes before output is created; I/O failures retain partial output.".
-spec write(hls_source_config:transport() | file:filename() | build(), file:filename()) -> descriptor().
write(Input, Output) ->
    hls_generated_files:write(emit(Input), Output).

-doc "Compiles the trusted sources list of {file, compiler options} pairs, invokes topology {module, function, arguments}, and elaborates within actor_limit. Checks direct/buffered routes, source-derived captures, publishers, startup and optional rectangle ingress. Optional protocol_model => {Module, Options} invokes an application-owned hls_protocol_model provider on the fresh inventory. Its checked graph establishes neither source refinement nor progress admission. Does not create output files. Loads declared source modules into the VM; constructors are trusted build code and may themselves have effects. Each distinct actor module is lowered once; capture analysis and all placements share that complete compiler program. Owner, port and inbox hardware is rendered only by emit/1.".
-spec prepare(hls_source_config:config()) -> program().
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
    Programs = maps:map(fun(_, #{program := P}) -> P end, Modules),
    Producers = maps:from_list([{Id, maps:get(M, Programs)} || #{id := Id, module := M} <- Actors]),
    Capture = hls_protocol_capture:plan(Inventory, Producers),
    Effects = maps:map(fun(_, P) -> xls_actor_program:entry_effects(P) end, Programs),
    Entries = maps:from_list([{Id, maps:get(M, Effects)} || #{id := Id, module := M} <- Actors]),
    Transactions = hls_protocol_transactions:plan(Inventory, Entries),
    Publishers = hls_protocol_source:plan(Bundle, Transactions, Capture),
    %% State invariants are outside this build boundary; literal source projections need none.
    true = lists:all(fun(#{constant_requirements := Requirements}) -> Requirements =:= [] end,
        [R || #{outputs := Outputs} <- maps:get(sources, Publishers), #{rows := Rows} <- Outputs, R <- Rows]),
    Inbox = hls_protocol_inbox:plan(Capture),
    #program{bundle = Bundle, capture = Capture, transactions = Transactions,
        sources = Publishers, inbox = Inbox, fabric = hls_protocol_fabric:plan(Publishers, Inbox),
        ingress = hls_protocol_control:plan(Bundle), model = Model}.

-doc "Returns the source bundle for downstream placement and host-codec binding. Treat it as read-only and retain the program's source modules; this accessor does not validate supplied bundles.".
-spec bundle(program()) -> bundle().
bundle(#program{bundle = Bundle}) -> Bundle.

-doc "Returns the whole source control plan before native placement. Host bindings retain recipients assigned to BEAM or another device; the transport descriptor's ingress is only the native projection.".
-spec control(program()) -> none | hls_protocol_control:plan().
control(#program{ingress = Control}) -> Control.

-doc "Prepares one source program and plans its transport without creating output files. Accepts prepare/1 configuration plus plan/2's native_actors and arithmetic_groups options.".
-spec plan(hls_source_config:config()) -> build().
plan(Config) ->
    plan(prepare(Config), maps:with([native_actors, arithmetic_groups], Config)).

-doc "Derives a placement from one unchanged source program without source reads or file writes. Options accepts only native_actors and arithmetic_groups. Omitted native_actors selects all actors; otherwise require a nonempty proper subset of unique logical IDs. Groups select disjoint source-compatible scalar completions, local by default. Checks source-bound receiver layouts without rendering hardware, retaining global indices and canonical crossing ports. Ordinary receivers import their one source owner definition; this removes duplicated DSLX compilation, not independent actor state or hardware. These ports still require ordered delivery, common clock/reset and stable offers; no framing or independent reset protocol is added here.".
-spec plan(program(), hls_source_config:placement_options()) -> build().
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
        #{module => M, file => list_to_binary(Relative), manifest => hls_local_actor:descriptor(Artifact)}
    end || {I, M} <- lists:enumerate(0, Used)],
    {Receivers, Layouts} = lists:unzip([begin
        Incoming = [L || L = #{destination_index := D} <- maps:get(links, Fabric), D =:= I],
        Messages = lists:append([Ms || #{target := Target, messages := Ms} <- maps:get(startup,Topology), Target =:= Id]),
        Owner = hls_protocol_arithmetic:select(I, Arithmetic, maps:get(M, Modules)),
        Layout = hls_protocol_inbox:plan(Owner, Incoming, Capture, Messages, hls_protocol_control:addressed(Ingress,I)),
        Source = case maps:get(mode, maps:get(completion, Owner, #{mode => local})) of
            shared -> Owner;
            local -> [File] = [F || #{module := Mod, file := F} <- ActorFunctions, Mod =:= M],
                Owner#{owner_import => #{file => File}}
        end,
        Interface = hls_local_actor:descriptor(Source#{inbox => hls_protocol_inbox:descriptor(Layout)}),
        Relative = filename:join("actors", "receiver_" ++ integer_to_list(I) ++ ".x"),
        {#{index => I, module => M, file => list_to_binary(Relative), manifest => Interface},
            #receiver{source = Source, layout = Layout}}
    end || {I, #{id := Id, module := M}} <- lists:enumerate(0, Actors), lists:member(I, Native)]),
    Transport = #{arithmetic => Arithmetic, bundle => Bundle, capture => Capture, transactions => Transactions,
        sources => Publishers, inbox => Inbox, fabric => Fabric, ingress => Ingress, whole_control => WholeIngress,
        actor_functions => ActorFunctions, receivers => Receivers},
    Plan = case Model of none -> Transport; _ -> Transport#{protocol_model => Model} end,
    #build{transport = Plan, receivers = Layouts}.

-doc "Returns the static transport descriptor without rendering owners or inboxes. Source snapshots, receiver layouts and imported filenames are present; generated DSLX and byte hashes are absent. emit/1 returns and saves the finalized descriptor as transport.etf. Treat both as read-only.".
-spec descriptor(build()) -> descriptor().
descriptor(#build{transport = Transport}) -> Transport.

-doc "Returns relative filenames with IO data and the transport descriptor, without writing output. A trusted config map is prepared and planned; a filename is consulted as one config map and follows that same path, with source paths relative to the caller. An unchanged in-process build needs no source rereads. Source constructors may have effects; template reads remain. Saved ETF plans are not accepted as configuration.".
-spec emit(hls_source_config:transport() | file:filename() | build()) -> hls_generated_files:output(descriptor()).
emit(#build{transport = Static = #{bundle := Bundle = #{modules := Sources}, fabric := Fabric,
        actor_functions := Functions, receivers := Interfaces}, receivers = Layouts}) ->
    Modules = maps:map(fun(_, Source) -> hls_local_actor:render(Source) end, Sources),
    FunctionArtifacts = [maps:get(M, Modules) || #{module := M} <- Functions],
    ReceiverArtifacts = [hls_protocol_inbox:attach(receiver_owner(Source, maps:get(M, Modules)), Layout)
        || {#{module := M}, #receiver{source = Source, layout = Layout}} <- lists:zip(Interfaces, Layouts)],
    ActorFunctions = [D#{manifest := hls_local_actor:manifest(A)} || {D, A} <- lists:zip(Functions, FunctionArtifacts)],
    Receivers = [D#{manifest := hls_local_actor:manifest(A)} || {D, A} <- lists:zip(Interfaces, ReceiverArtifacts)],
    Plan = Static#{bundle := Bundle#{modules := Modules}, actor_functions := ActorFunctions, receivers := Receivers},
    Actors = [hls_local_actor:emit(Artifact, binary_to_list(Relative))
        || {#{file := Relative}, Artifact} <- lists:zip(Functions ++ Interfaces, FunctionArtifacts ++ ReceiverArtifacts)],
    #{files := TransportFiles} = xls_protocol_transport:emit(Fabric),
    ModelFiles = hls_protocol_model:emit(maps:get(protocol_model, Plan, none)),
    Summary = #{actors => length(Receivers), links => length(maps:get(links, Fabric)),
        source_modules => lists:sort(maps:keys(Modules)), top => protocol_fabric, eligible => false,
        source_plans => maps:map(fun(_, #{program := P}) -> maps:with([source_sha256, artifact_sha256, planner_md5],
            xls_statem_plan:manifest(xls_actor_program:plan(P))) end, Modules),
        actor_functions => ActorFunctions, receivers => Receivers, actor_runtime => false, hardware => dslx, rtl => []},
    Generated = hls_generated_files:merge(Actors ++ [
        hls_generated_files:prefix("dslx", TransportFiles), ModelFiles,
        #{"transport.etf" => term_to_binary(Plan, [deterministic]), "summary.json" => json:encode(Summary)}]),
    #{files => Generated, result => Plan};
emit(Config) when is_map(Config) -> emit(plan(Config));
emit(Filename) -> emit(hls_source_config:read(Filename)).

%% Load only declared current source; no historical backend overlay enters the code path.
-spec load(file:filename(), [hls_source:compiler_option()]) -> module().
load(File, Options) ->
    {ok, M, Bytes} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
    {module, M} = code:load_binary(M, File, Bytes), M.

%% The parse transform's context retains includes and preprocessing options.
-spec compile(module()) -> hls_local_actor:source().
compile(Module) ->
    [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
    Artifact = hls_local_actor:prepare(maps:get(source_name, Context), Context),
    Artifact#{context => Context}.

%% Independent destination acceptance implements direct and buffered delivery only.
-spec delivery(hls_protocol_topology:route()) -> ok.
delivery(#{delivery := Mode}) when Mode =:= direct; Mode =:= buffered -> ok;
delivery(#{source := Source, delivery := Mode}) -> error({unsupported_transport_delivery, Source, Mode}).

%% Render a shared ABI or import the already rendered ordinary owner. Layout planning
%% binds the file; only emission can bind its generated-byte identity.
-spec receiver_owner(hls_local_actor:source(), hls_local_actor:artifact()) -> hls_local_actor:artifact().
receiver_owner(Source = #{completion := #{mode := shared}}, _) -> hls_local_actor:render(Source);
receiver_owner(#{owner_import := #{file := File}}, Owner = #{dslx := Bytes}) ->
    Name = filename:basename(binary_to_list(File), ".x"),
    {ok, Template} = file:read_file(filename:join(code:priv_dir(hls_fabric), "xls/templates/local_owner_import.x.in")),
    Owner#{dslx := xls_template:render(Template, [{<<"@@MODULE@@">>, Name}]),
        owner_import => #{file => File, dslx_sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase)}}.
