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
    receivers := [actor_descriptor()], transition := xls_protocol_transport:descriptor(), protocol_model => hls_protocol_model:report()}.

%% Source-wide facts are shared by every placement; role selection never recompiles them.
-record(program, {bundle :: bundle(), capture :: hls_protocol_capture:plan(),
    transactions :: hls_protocol_transactions:plan(), sources :: hls_protocol_source:plan(),
    inbox :: hls_protocol_inbox:plan(), fabric :: hls_protocol_fabric:plan(),
    ingress :: none | hls_protocol_control:plan(), model :: none | hls_protocol_model:report()}).
%% A receiver's interface, checked source ownership and inbox layout travel together.
-record(receiver, {descriptor :: actor_descriptor(), source :: hls_local_actor:source(),
    layout :: hls_protocol_inbox:layout()}).
%% Placement retains source-wide facts by reference; public descriptors are derived views.
-record(build, {program :: program(), fabric :: hls_protocol_fabric:plan(),
    ingress :: none | hls_protocol_control:plan(), arithmetic :: [hls_protocol_arithmetic:group()],
    functions :: [actor_descriptor()], receivers = [] :: [#receiver{}], hardware :: xls_protocol_transport:plan()}).
%% Each rendered actor couples its finalized interface to its exact generated files.
-record(emitted_actor, {descriptor :: actor_descriptor(), files :: hls_generated_files:files()}).

-doc "One checked source program from prepare/1, shared across placements within a build. Contains source artifacts and topology, not an output directory or hardware admission. Keep it in process and do not edit it or reload its source modules while deriving roles; it is not a saved-plan input format.".
-opaque program() :: #program{}.

-doc "A checked transport placement from plan/1 or plan/2, with checked receiver layouts ready for rendering. Retain it unchanged in process; it grants no capacity, progress or device admission.".
-opaque build() :: #build{}.

-doc "Writes emit/1's generated files to a fresh directory and returns the transport descriptor. Accepts a trusted source config map or filename, or an unchanged in-process build. Generation finishes before output is created; I/O failures retain partial output.".
-spec write(hls_source_config:transport() | file:filename() | build(), file:filename()) -> descriptor().
write(Input, Output) ->
    hls_generated_files:write(emit(Input), Output).

-doc "Loads the declared sources, invokes the trusted topology constructor and lowers each distinct actor module once. Checks source inventories, captures, publishers, startup and optional rectangle control before placement. All roles share the retained compiler programs; owner and inbox hardware is rendered only by emit/1. Creates no output files. Constructors may have effects; retain the loaded source modules while deriving placements. Optional protocol-model checks establish neither source refinement nor progress admission.".
-spec prepare(hls_source_config:config()) -> program().
prepare(Config = #{sources := Sources, topology := Constructor, actor_limit := Limit}) ->
    Loaded = load_sources(Sources),
    Topology = prepare_topology(Constructor, Limit, Loaded),
    Modules = prepare_actors(Topology, Loaded),
    Inventory = inspect_sources(Topology, Modules),
    Model = hls_protocol_model:check(maps:get(protocol_model, Config, none), Inventory),
    Bundle = #{topology => Topology, modules => Modules, inventory => Inventory},
    prepare_transport(Bundle, Model).

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

-doc "Plans native placement and optional shared arithmetic from one unchanged source program. Options accepts only native_actors and arithmetic_groups; omitted placement selects all actors. Checks receiver layouts and retains normalized transport transitions without source reads or hardware rendering. Global actor indices and crossing ports remain stable. Ordinary receivers share their source module's generated functions, while retaining independent state. Ordered delivery, common clock/reset and stable offers remain caller obligations.".
-spec plan(program(), hls_source_config:placement_options()) -> build().
plan(Program = #program{bundle = Bundle = #{topology := #{actors := Actors}, modules := Modules},
        capture = Capture, fabric = WholeFabric, ingress = WholeIngress}, Options) ->
    check_placement_options(Options),
    #{fabric := Fabric, ingress := Ingress, indices := Native} = hls_protocol_partition:plan(
        Options, Bundle, Capture, WholeFabric, WholeIngress),
    Arithmetic = hls_protocol_arithmetic:plan(maps:get(arithmetic_groups, Options, []), Bundle, Native),
    Build = #build{program = Program, fabric = Fabric, ingress = Ingress,
        arithmetic = Arithmetic, functions = function_descriptors(Modules), hardware = xls_protocol_transport:plan(Fabric)},
    Receivers = [plan_receiver(Index, Actor, Build)
        || {Index, Actor} <- lists:enumerate(0, Actors), lists:member(Index, Native)],
    Build#build{receivers = Receivers}.

-doc "Returns a static view of the retained source snapshots, receiver interfaces and import filenames. Generated DSLX and byte hashes are absent; emit/1 returns and saves the finalized descriptor as transport.etf. Treat both views as read-only.".
-spec descriptor(build()) -> descriptor().
descriptor(Build = #build{program = #program{bundle = Bundle}, functions = Functions, receivers = Receivers}) ->
    transport_descriptor(Build, Bundle, Functions, [D || #receiver{descriptor = D} <- Receivers]).

-doc "Returns relative filenames with IO data and the finalized transport descriptor, without writing output. Config maps are prepared and planned; filenames are consulted as config maps with source paths relative to the caller. A retained build needs no source rereads, but emission reads templates. Saved ETF descriptors are not configuration.".
-spec emit(hls_source_config:transport() | file:filename() | build()) -> hls_generated_files:output(descriptor()).
emit(Build = #build{program = #program{bundle = Bundle = #{modules := Sources}},
        functions = FunctionDescriptors, receivers = ReceiverPlans, hardware = Hardware}) ->
    Modules = maps:map(fun(_, Source) -> hls_local_actor:render(Source) end, Sources),
    Functions = [emit_actor(D, maps:get(Module, Modules)) || D = #{module := Module} <- FunctionDescriptors],
    Receivers = [emit_receiver(Receiver, Modules) || Receiver <- ReceiverPlans],
    Plan = transport_descriptor(Build, Bundle#{modules := Modules},
        [D || #emitted_actor{descriptor = D} <- Functions],
        [D || #emitted_actor{descriptor = D} <- Receivers]),
    ActorFiles = [Files || #emitted_actor{files = Files} <- Functions ++ Receivers],
    #{files => transport_files(Plan, Hardware, ActorFiles), result => Plan};
emit(Config) when is_map(Config) -> emit(plan(Config));
emit(Filename) -> emit(hls_source_config:read(Filename)).

%% Declared modules are loaded in source order, with duplicate ownership rejected before elaboration.
-spec load_sources([hls_source_config:source_file()]) -> [module()].
load_sources(Sources) ->
    Loaded = [load(File, Options) || {File, Options} <- Sources],
    case length(Loaded) =:= length(lists:usort(Loaded)) of
        true -> Loaded;
        false -> hls_diagnostic:raise(source, duplicate_transport_source,
            <<"Declare each source module once.">>, #{modules => Loaded, path => [sources]})
    end.

%% Only the declared, exported constructor may elaborate the source graph.
-spec prepare_topology(hls_source_config:topology(), pos_integer(), [module()]) -> hls_protocol_topology:plan().
prepare_topology({Module, Function, Arguments}, Limit, Loaded) ->
    case lists:member(Module, Loaded) of
        true -> ok;
        false -> hls_diagnostic:raise(source, missing_topology_module,
            <<"The topology constructor's module must appear in sources.">>,
            #{module => Module, path => [topology], source_modules => Loaded})
    end,
    case erlang:function_exported(Module, Function, length(Arguments)) of
        true -> ok;
        false -> hls_diagnostic:raise(topology, missing_topology_constructor,
            <<"Export the configured topology constructor with the supplied arity.">>,
            #{module => Module, function => Function, arity => length(Arguments), path => [topology]})
    end,
    Normal = hls_topology:normalize(apply(Module, Function, Arguments)),
    Topology = #{routes := Routes} = hls_protocol_topology:elaborate(Normal, Limit),
    lists:foreach(fun delivery/1, Routes),
    Topology.

%% Compile each distinct actor module once, retaining every affected logical actor in diagnostics.
-spec prepare_actors(hls_protocol_topology:plan(), [module()]) -> #{module() => hls_local_actor:source()}.
prepare_actors(#{actors := Actors}, Loaded) ->
    Missing = [#{actor => Id, module => Module} || #{id := Id, module := Module} <- Actors,
        not lists:member(Module, Loaded)],
    case Missing of
        [] -> ok;
        _ -> hls_diagnostic:raise(source, missing_actor_modules,
            <<"Every actor module used by the topology must appear in sources.">>,
            #{actors => Missing, path => [sources]})
    end,
    Used = lists:usort([Module || #{module := Module} <- Actors]),
    maps:from_list([{Module, hls_diagnostic:with_context(
        #{module => Module, actors => [Id || #{id := Id, module := Owner} <- Actors, Owner =:= Module]},
        fun() -> compile(Module) end)} || Module <- Used]).

%% Inventory diagnostics retain their original ordering and detailed source contexts.
-spec inspect_sources(hls_protocol_topology:plan(), #{module() => hls_local_actor:source()}) -> hls_protocol_inventory:report().
inspect_sources(Topology, Modules) ->
    Inventory = hls_protocol_inventory:inspect(Topology, Modules),
    case maps:get(diagnostics, Inventory) of
        [] -> Inventory;
        [#{code := Code, context := Context, message := Message} | _] = Diagnostics ->
            hls_diagnostic:raise(inventory, Code, Message, Context#{diagnostics => Diagnostics})
    end.

%% Publication, capture and inbox plans all derive from the same compiler programs and inventory.
-spec prepare_transport(bundle(), none | hls_protocol_model:report()) -> program().
prepare_transport(Bundle = #{topology := #{actors := Actors}, modules := Modules, inventory := Inventory}, Model) ->
    Programs = maps:map(fun(_, #{program := Program}) -> Program end, Modules),
    Producers = maps:from_list([{Id, maps:get(Module, Programs)} || #{id := Id, module := Module} <- Actors]),
    Capture = hls_protocol_capture:plan(Inventory, Producers),
    Effects = maps:map(fun(_, Program) -> xls_actor_program:entry_effects(Program) end, Programs),
    Entries = maps:from_list([{Id, maps:get(Module, Effects)} || #{id := Id, module := Module} <- Actors]),
    Transactions = hls_protocol_transactions:plan(Inventory, Entries),
    Publishers = hls_protocol_source:plan(Bundle, Transactions, Capture),
    %% State invariants are outside this build boundary; literal source projections need none.
    true = lists:all(fun(#{constant_requirements := Requirements}) -> Requirements =:= [] end,
        [Row || #{outputs := Outputs} <- maps:get(sources, Publishers), #{rows := Rows} <- Outputs, Row <- Rows]),
    Inbox = hls_protocol_inbox:plan(Capture),
    #program{bundle = Bundle, capture = Capture, transactions = Transactions,
        sources = Publishers, inbox = Inbox, fabric = hls_protocol_fabric:plan(Publishers, Inbox),
        ingress = hls_protocol_control:plan(Bundle), model = Model}.

%% Placement cannot silently ignore options belonging to a different build stage.
-spec check_placement_options(hls_source_config:placement_options()) -> ok.
check_placement_options(Options) ->
    case maps:keys(maps:without([native_actors, arithmetic_groups], Options)) of
        [] -> ok;
        Unknown -> hls_diagnostic:raise(transport, unsupported_transport_options,
            <<"Transport placement accepts native_actors and arithmetic_groups only.">>,
            #{options => lists:sort(Unknown)})
    end.

%% Stable module order gives ordinary owners one filename independently of native placement.
-spec function_descriptors(#{module() => hls_local_actor:source() | hls_local_actor:artifact()}) -> [actor_descriptor()].
function_descriptors(Modules) ->
    [#{module => Module, file => actor_filename("actor", Index),
        manifest => hls_local_actor:descriptor(maps:get(Module, Modules))}
        || {Index, Module} <- lists:enumerate(0, lists:sort(maps:keys(Modules)))].

%% Each receiver owns its source, interface and checked inbox together; global indices remain stable.
-spec plan_receiver(non_neg_integer(), hls_protocol_topology:actor(), build()) -> #receiver{}.
plan_receiver(Index, #{id := Id, module := Module},
        #build{program = #program{bundle = #{topology := #{startup := Startup}, modules := Modules}, capture = Capture},
            fabric = #{links := Links}, ingress = Ingress, arithmetic = Arithmetic, functions = Functions}) ->
    Incoming = [Link || Link = #{destination_index := Destination} <- Links, Destination =:= Index],
    Messages = lists:append([Batch || #{target := Target, messages := Batch} <- Startup, Target =:= Id]),
    Owner = hls_protocol_arithmetic:select(Index, Arithmetic, maps:get(Module, Modules)),
    Layout = hls_protocol_inbox:plan(Owner, Incoming, Capture, Messages,
        hls_protocol_control:addressed(Ingress, Index)),
    Source = receiver_source(Owner, Module, Functions),
    Interface = hls_local_actor:descriptor(Source#{inbox => hls_protocol_inbox:descriptor(Layout)}),
    Descriptor = #{index => Index, module => Module, file => actor_filename("receiver", Index), manifest => Interface},
    #receiver{descriptor = Descriptor, source = Source, layout = Layout}.

%% Shared completion keeps its specialized owner; ordinary receivers import their source module.
-spec receiver_source(hls_local_actor:source(), module(), [actor_descriptor()]) -> hls_local_actor:source().
receiver_source(Owner, Module, Functions) ->
    case maps:get(mode, maps:get(completion, Owner, #{mode => local})) of
        shared -> Owner;
        local ->
            [File] = [Path || #{module := SourceModule, file := Path} <- Functions, SourceModule =:= Module],
            Owner#{owner_import => #{file => File}}
    end.

%% Function and receiver paths retain their existing serialized identities.
-spec actor_filename(string(), non_neg_integer()) -> binary().
actor_filename(Kind, Index) ->
    list_to_binary(filename:join("actors", Kind ++ "_" ++ integer_to_list(Index) ++ ".x")).

%% Static and emitted views share structure; only the supplied module artifacts and actor manifests differ.
-spec transport_descriptor(build(), bundle(), [actor_descriptor()], [actor_descriptor()]) -> descriptor().
transport_descriptor(#build{program = #program{capture = Capture, transactions = Transactions,
        sources = Publishers, inbox = Inbox, ingress = WholeIngress, model = Model},
        fabric = Fabric, ingress = Ingress, arithmetic = Arithmetic, hardware = Hardware}, Bundle, Functions, Receivers) ->
    Transport = #{arithmetic => Arithmetic, bundle => Bundle, capture => Capture, transactions => Transactions,
        sources => Publishers, inbox => Inbox, fabric => Fabric, ingress => Ingress, whole_control => WholeIngress,
        actor_functions => Functions, receivers => Receivers, transition => xls_protocol_transport:descriptor(Hardware)},
    case Model of
        none -> Transport;
        _ -> Transport#{protocol_model => Model}
    end.

%% Render only the receiver's retained ownership/layout and its already rendered ordinary source module.
-spec emit_receiver(#receiver{}, #{module() => hls_local_actor:artifact()}) -> #emitted_actor{}.
emit_receiver(#receiver{descriptor = Descriptor = #{module := Module}, source = Source, layout = Layout}, Modules) ->
    Owner = receiver_owner(Source, maps:get(Module, Modules)),
    emit_actor(Descriptor, hls_protocol_inbox:attach(Owner, Layout)).

%% Finalized metadata and sidecar files are bound to one exact artifact, without positional list joins.
-spec emit_actor(actor_descriptor(), hls_local_actor:artifact()) -> #emitted_actor{}.
emit_actor(Descriptor = #{file := Relative}, Artifact) ->
    #emitted_actor{descriptor = Descriptor#{manifest := hls_local_actor:manifest(Artifact)},
        files = hls_local_actor:emit(Artifact, binary_to_list(Relative))}.

%% Package finalized actors, fabric and reports without changing public file names or manifest schemas.
-spec transport_files(descriptor(), xls_protocol_transport:plan(), [hls_generated_files:files()]) -> hls_generated_files:files().
transport_files(Plan = #{bundle := #{modules := Modules}, fabric := Fabric,
        actor_functions := Functions, receivers := Receivers}, Hardware, ActorFiles) ->
    #{files := TransportFiles} = xls_protocol_transport:emit(Hardware),
    ModelFiles = hls_protocol_model:emit(maps:get(protocol_model, Plan, none)),
    Summary = #{actors => length(Receivers), links => length(maps:get(links, Fabric)),
        source_modules => lists:sort(maps:keys(Modules)), top => protocol_fabric, eligible => false,
        source_plans => maps:map(fun(_, #{program := Program}) -> maps:with([source_sha256, artifact_sha256, planner_md5],
            xls_statem_plan:manifest(xls_actor_program:plan(Program))) end, Modules),
        actor_functions => Functions, receivers => Receivers, actor_runtime => false, hardware => dslx, rtl => []},
    hls_generated_files:merge(ActorFiles ++ [
        hls_generated_files:prefix("dslx", TransportFiles), ModelFiles,
        #{"transport.etf" => term_to_binary(Plan, [deterministic]), "summary.json" => json:encode(Summary)}]).

%% Both backends share the same structured source diagnostics and captured build context.
-spec load(file:filename(), [hls_source:compiler_option()]) -> module().
load(File, Options) -> hls_build_sources:load(File, Options).

%% The parse transform's context retains includes and preprocessing options.
-spec compile(module()) -> hls_local_actor:source().
compile(Module) ->
    Context = case proplists:get_value(hls_source_context, Module:module_info(attributes)) of
        [Captured] -> Captured;
        undefined -> hls_diagnostic:raise(source, missing_actor_source_context,
            <<"Compile the actor with its HLS parse transform and without deterministic metadata removal.">>,
            #{module => Module})
    end,
    Source = maps:get(source_name, Context),
    Artifact = hls_diagnostic:with_context(#{module => Module, source => unicode:characters_to_binary(Source)},
        fun() -> hls_local_actor:prepare(Source, Context) end),
    Artifact#{context => Context}.

%% Independent destination acceptance implements direct and buffered delivery only.
-spec delivery(hls_protocol_topology:route()) -> ok.
delivery(#{delivery := Mode}) when Mode =:= direct; Mode =:= buffered -> ok;
delivery(#{source := {Actor, Port}, delivery := Mode}) ->
    hls_diagnostic:raise(transport, unsupported_transport_delivery,
        <<"Source transport supports direct and buffered delivery only.">>,
        #{actor => Actor, port => Port, value => Mode, supported => [direct, buffered]}).

%% Render a shared ABI or import the already rendered ordinary owner. Layout planning
%% binds the file; only emission can bind its generated-byte identity.
-spec receiver_owner(hls_local_actor:source(), hls_local_actor:artifact()) -> hls_local_actor:artifact().
receiver_owner(Source = #{completion := #{mode := shared}}, _) -> hls_local_actor:render(Source);
receiver_owner(#{owner_import := #{file := File}}, Owner = #{dslx := Bytes}) ->
    Name = filename:basename(binary_to_list(File), ".x"),
    {ok, Template} = file:read_file(filename:join(code:priv_dir(hls_fabric), "xls/templates/local_owner_import.x.in")),
    Owner#{dslx := xls_template:render(Template, [{<<"@@MODULE@@">>, Name}]),
        owner_import => #{file => File, dslx_sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase)}}.
