-module(phi_protocol_model_tests).
-moduledoc "Synthetic dependency-model checks; role annotations do not prove source semantics.".
-include_lib("eunit/include/eunit.hrl").

%% Two labelled ports to one PID remain distinct ordered publications, not a deduplicated neighbor.
-spec repeated_neighbor_test() -> ok.
repeated_neighbor_test() ->
    {Inventory, Contracts} = fixture(),
    #{messages := Messages, edges := Edges, source_refinement := unestablished,
      startup_marking := unestablished, whole_protocol_eligible := false} =
        phi_protocol_model:derive(Inventory, Contracts),
    ?assertEqual(28, length(Messages)),
    lists:foreach(fun(K) ->
        First = {capture,a,b,east,phi,K}, Last = {capture,a,b,west,phi,K},
        ?assert(lists:member(#{waiter=>Last,prerequisite=>First,lag=>0,kind=>sender_order}, Edges))
    end, lists:seq(0,11)).

%% Distinct layouts do not impose a source order between mutually exclusive publications.
-spec alternatives_test() -> ok.
alternatives_test() ->
    {I=#{channels:=[C|Cs]}, Contracts} = fixture(),
    #{edges:=Edges} = phi_protocol_model:derive(
        I#{channels:=[C#{alternatives:=[#{phase=>gathering,layout=>other,order=>0}]}|Cs]},Contracts),
    ?assertEqual(2, length([E || E=#{kind:=sender_order} <- Edges])).

%% Missing, duplicate and incompatible annotations/edges must reject, not disappear from the model.
-spec rejected_model_test() -> ok.
rejected_model_test() ->
    {I=#{actors:=Actors,channels:=[C|Cs]}, Contracts=#{owner:=Role}} = fixture(),
    ?assertError({periodic_model,incomplete_role_annotations},phi_protocol_model:derive(I,#{})),
    ?assertError({periodic_model,incomplete_role_annotations},phi_protocol_model:derive(I,Contracts#{unused=>Role})),
    ?assertError({periodic_model,duplicate_or_empty_actor_population},phi_protocol_model:derive(I#{actors:=Actors++Actors},Contracts)),
    ?assertError({periodic_model,duplicate_periodic_channel},phi_protocol_model:derive(I#{channels:=[C,C|Cs]},Contracts)),
    ?assertError({periodic_model,{phase_coverage,owner}},phi_protocol_model:derive(I,Contracts#{owner:=Role#{phases:=[gathering]}})),
    ?assertError({periodic_model,{unsupported_role,owner,unknown}},phi_protocol_model:derive(I,Contracts#{owner:=Role#{role:=unknown}})),
    lists:foreach(fun(R)->
        ?assertError({periodic_model,{rounds,owner,R}},phi_protocol_model:derive(I,Contracts#{owner:=Role#{rounds:=R}}))
    end,[0,257,1.5]),
    ?assertError({periodic_model,{publication_phase,a,east,phi}},phi_protocol_model:derive(
        I#{channels:=[C#{alternatives:=[#{phase=>flipping,layout=>1,order=>0}]}|Cs]},Contracts)),
    ?assertError({periodic_model,{unsupported_schema,unexpected}},phi_protocol_model:derive(I#{channels:=[C#{tag:=unexpected}|Cs]},Contracts)),
    ?assertError({periodic_model,{source_diagnostics,[unsupported]}},phi_protocol_model:derive(I#{diagnostics:=[unsupported]},Contracts)),
    ?assertError({badkey,absent},phi_protocol_model:derive(I#{channels:=[C#{destination:={actor,absent}}|Cs]},Contracts)).

%% A deliberately limited proposed model makes no assertion that these synthetic owners execute it.
-spec fixture() -> {map(),map()}.
fixture() ->
    Phases=[configuring,measuring,gathering,comparing,flipping],
    Channels=[#{source=>a,destination=>{actor,b},port=>Port,tag=>Tag,
        alternatives=>[#{phase=>Phase,layout=>Phase,order=>Order}]} ||
        {Tag,Phase}<-[{phi,gathering},{phi0,comparing},{anyon_move,flipping}],
        {Port,Order}<-[{east,0},{west,1}]],
    {#{actors=>[#{id=>a,module=>owner},#{id=>b,module=>owner}],channels=>Channels,
       modules=>#{owner=>#{phases=>Phases}},diagnostics=>[]},
     #{owner=>#{role=>phi,phases=>Phases,rounds=>12}}}.

%% Fresh source inventories cover periodic N2/N3/N6 lines and D3 halo multiplicity without XLS.
-spec source_models_test_() -> term().
source_models_test_() -> {timeout, 120, fun source_models/0}.

%% Compile each source once, then check all finite topologies against their explicit annotations.
-spec source_models() -> ok.
source_models() ->
    Compiler = code:lib_dir(erl_hls),
    Source = filename:join(Compiler, "src/examples/phi_decoder"),
    Options = [{i, filename:join(Compiler, "include")}, {i, Source}],
    Modules = [phi_halo_cell, phenom_data_cell, phenom_syndrome_cell,
        phi_line_cell, phenom_line_data_cell, phenom_line_syndrome_cell],
    lists:foreach(fun(M) ->
        File = filename:join(Source, atom_to_list(M) ++ ".erl"),
        {ok, M, Binary} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
        {module, M} = code:load_binary(M, File, Binary)
    end, Modules ++ [phi_noise_topology, phi_repetition_topology]),
    Artifacts = maps:from_list([begin
        [Context] = proplists:get_value(hls_source_context, M:module_info(attributes)),
        Program = xls_actor_program:from_file(maps:get(source_name, Context), Context),
        {M, #{program => Program}}
    end || M <- Modules]),
    Cases = [{phi_repetition_topology:topology(N, 16#80000000), line, 3 * N, 34 * N} || N <- [2, 3, 6]] ++
        [{phi_noise_topology:topology(3, 16#80000000), halo, 54, 1188}],
    lists:foreach(fun({Topology, Kind, ActorCount, MessageCount}) ->
        Expanded = #{actors := Actors} = hls_protocol_topology:elaborate(hls_topology:normalize(Topology), 64),
        Used = maps:with(lists:usort([M || #{module := M} <- Actors]), Artifacts),
        Inventory = hls_protocol_inventory:inspect(Expanded, Used),
        Report = #{model := Model} = hls_protocol_model:check({phi_protocol_model, contracts(Kind)}, Inventory),
        ?assertEqual(ActorCount, maps:get(actor_count, Model)),
        ?assertEqual(MessageCount, length(maps:get(messages, Model))),
        check_report(Inventory, Report)
    end, Cases),
    ok.

%% Coverage is computed independently from schema and diffusion count; reverse a real dependency as a negative.
-spec check_report(map(), hls_protocol_model:report()) -> ok.
check_report(#{channels := Channels}, #{analysis := #{ranks := Ranks},
        model := #{nodes := Nodes, edges := Edges, messages := Messages,
            source_refinement := unestablished, startup_marking := unestablished, whole_protocol_eligible := false}}) ->
    ?assertEqual(lists:sort(Nodes), lists:sort(maps:keys(Ranks))),
    lists:foreach(fun
        (#{lag := 0, waiter := W, prerequisite := P}) -> ?assert(maps:get(P, Ranks) < maps:get(W, Ranks));
        (#{lag := 1}) -> ok
    end, Edges),
    Expected = lists:sort(lists:append([[{S, D, P, T, K} || K <- case T of phi -> lists:seq(0, 11); _ -> [0] end]
        || #{source := S, destination := {actor, D}, port := P, tag := T} <- Channels])),
    ?assertEqual(Expected, lists:sort([{S, D, P, T, K} || #{key := {S, D, P, T}, iteration := K} <- Messages])),
    [#{waiter := W, prerequisite := P} | _] = [E || E = #{lag := 0} <- Edges],
    ?assertMatch({error, {same_generation_wait_cycle, _}}, hls_protocol_wait_graph:check(Nodes,
        [#{waiter => P, prerequisite => W, lag => 0, kind => dependency} | Edges])),
    ok.

%% Keep model hypotheses beside this application's tests, independent of transport or compiler selection.
-spec contracts(line | halo) -> map().
contracts(Kind) ->
    {D, S, P} = case Kind of
        line -> {phenom_line_data_cell, phenom_line_syndrome_cell, phi_line_cell};
        halo -> {phenom_data_cell, phenom_syndrome_cell, phi_halo_cell}
    end,
    #{D => #{role => data, phases => [configuring, collecting, reporting, replying]},
      S => #{role => syndrome, phases => [configuring, collecting, announcing]},
      P => #{role => phi, rounds => 12, phases => [configuring, measuring, gathering, comparing, flipping]}}.

%% Exercise the ordinary public application builder and compare annotated/plain hardware and host bindings.
-spec application_build_test_() -> term().
application_build_test_() -> {timeout, 120, fun application_build/0}.

%% Analysis may add reports but cannot change hardware or manufacture an application admission.
-spec application_build() -> ok.
application_build() ->
    {application, Settings} = phi_protocol_config:repetition(2, #{}),
    Root = filename:join("_build", "phi-model-" ++ integer_to_list(erlang:system_time(nanosecond))),
    ok = file:make_dir(Root),
    Build = filename:join(Root, "annotated"), Plain = filename:join(Root, "plain"),
    Deployment = hls_protocol_application:write(Settings, Build),
    PlainDeployment = hls_protocol_application:write(maps:remove(protocol_model, Settings), Plain),
    Plan = #{bundle := #{inventory := Inventory}, protocol_model := Report} = read(Build, "transport.etf"),
    ?assertEqual(Report, read(Build, "protocol-model.etf")),
    ?assertEqual(binary:encode_hex(crypto:hash(sha256, term_to_binary(Inventory, [deterministic])), lowercase),
        maps:get(inventory_sha256, Report)),
    check_report(Inventory, Report),
    ?assertEqual(rename(maps:remove(protocol_model, Plan)), rename(read(Plain, "transport.etf"))),
    #{devices := #{board := Binding}} = Deployment,
    #{devices := #{board := PlainBinding}} = PlainDeployment,
    ?assertEqual(maps:remove(identity, Binding), maps:remove(identity, PlainBinding)),
    ?assertEqual(maps:remove(devices, Deployment), maps:remove(devices, PlainDeployment)),
    %% Unique compiler references still vary the identity constant; bind both gateways to the same exact identity.
    Compare = filename:join(Plain, "application-comparison"), ok = file:make_dir(Compare),
    ok = xls_protocol_application:write(Binding, Compare),
    ?assertEqual(file:read_file(filename:join(Build, "application/gateway.x")),
        file:read_file(filename:join(Compare, "gateway.x"))),
    Files = filelib:fold_files(Build, "\\.(x|sv)$", true, fun(F, Acc) -> [F | Acc] end, []),
    ?assert(Files =/= []),
    lists:foreach(fun(File) ->
        Relative = lists:nthtail(length(Build) + 1, File),
        case Relative of
            "application/gateway.x" -> ok;
            _ -> ?assertEqual(file:read_file(File), file:read_file(filename:join(Plain, Relative)))
        end
    end, Files),
    ?assertNot(filelib:is_file(filename:join(Plain, "protocol-model.etf"))),
    Failed = filename:join(Root, "rejected"),
    ?assertError({periodic_model, incomplete_role_annotations},
        hls_protocol_application:write(Settings#{protocol_model := {phi_protocol_model, #{}}}, Failed)),
    ?assertNot(filelib:is_dir(Failed)),
    ok.

%% Only trusted artifacts emitted by this test enter the full-term comparison.
-spec read(file:filename(), file:filename()) -> term().
read(Directory, File) ->
    {ok, Bytes} = file:read_file(filename:join(Directory, File)), binary_to_term(Bytes).

%% Normalize fresh symbolic origins bijectively; preserve sharing and every other field of the plan.
-spec rename(term()) -> term().
rename(Term) -> {Result, _} = rename(Term, #{}), Result.

%% Sorted map keys fix traversal order; this is test comparison, not a public artifact identity format.
-spec rename(term(), map()) -> {term(), map()}.
rename(Ref, Seen) when is_reference(Ref) ->
    Id = maps:get(Ref, Seen, map_size(Seen)), {{reference, Id}, Seen#{Ref => Id}};
rename(Map, Seen) when is_map(Map) ->
    {Pairs, Next} = rename(lists:sort(maps:to_list(Map)), Seen), {maps:from_list(Pairs), Next};
rename(Tuple, Seen) when is_tuple(Tuple) ->
    {Fields, Next} = rename(tuple_to_list(Tuple), Seen), {list_to_tuple(Fields), Next};
rename(List, Seen) when is_list(List) -> lists:mapfoldl(fun rename/2, Seen, List);
rename(Value, Seen) -> {Value, Seen}.
