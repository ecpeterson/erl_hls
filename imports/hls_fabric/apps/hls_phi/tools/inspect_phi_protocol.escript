#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).

%% Compile current example sources once and inventory their exact finite topology.
%% This entry point emits no RTL and authorizes no protocol removal or native run.
-spec main([string()]) -> ok.
main([ApplicationRoot,Output]) ->
    ok=file:make_dir(Output),
    Modules=[phi_halo_cell,phenom_data_cell,phenom_syndrome_cell,
             phi_line_cell,phenom_line_data_cell,phenom_line_syndrome_cell],
    All=Modules++[phi_noise_topology,phi_repetition_topology],
    SourceDir=filename:join(ApplicationRoot,"src"),
    lists:foreach(fun(M)->load(filename:join(SourceDir,atom_to_list(M)++".erl"),
        [{i,filename:join(ApplicationRoot,"include")},{i,SourceDir}]) end,All),
    Plans=maps:from_list([begin
        [Context]=proplists:get_value(hls_source_context,M:module_info(attributes)),
        Program=xls_actor_program:from_file(maps:get(source_name,Context),Context),
        {M,#{program=>Program,context=>Context}}
    end||M<-Modules]),
    ok=file:write_file(filename:join(Output,"source-plans.etf"),term_to_binary(Plans,[deterministic]),[exclusive]),
    Summaries=[inventory(Name,Topology,Plans,Output)||{Name,Topology}<-[
        {"repetition-2",phi_repetition_topology:topology(2,16#80000000)},
        {"repetition-3",phi_repetition_topology:topology(3,16#80000000)},
        {"repetition-6",phi_repetition_topology:topology(6,16#80000000)},
        {"noise-3",phi_noise_topology:topology(3,16#80000000)}]],
    Inputs=lists:usort([filename:join(SourceDir,atom_to_list(M)++".erl")||M<-All]++
        lists:append([maps:get(origins,maps:get(context,P),[])||P<-maps:values(Plans)])++
        [escript:script_name()]),
    Beams=[code:which(M)||M<-[xls_actor_program,xls_statem_plan,xls_statem_lower,
        xls_parse,xls_clause_lower,xls_record_codegen,xls_gs_immediate,
        hls_source,hls_actor_source,hls_records,hls_pack,hls_topology,
        hls_topology_family,hls_actor_interface,hls_protocol_topology,hls_protocol_inventory]],
    Report=#{eligible=>false,rtl_generated=>false,source_plans=>maps:map(fun(_,P)->source_summary(P) end,Plans),
        topologies=>Summaries,inputs=>[#{path=>list_to_binary(P),sha256=>digest(P)}||P<-Inputs],
        compiler_beams=>[#{path=>list_to_binary(P),sha256=>digest(P)}||P<-Beams]},
    ok=file:write_file(filename:join(Output,"summary.json"),json:encode(Report),[exclusive]),
    io:format("PHI_SOURCE_INVENTORY ~p modules ~p topologies; not admitted~n",[map_size(Plans),length(Summaries)]),
    case lists:any(fun(#{source_diagnostics:=N})->N=/=0 end,Summaries) of
        true -> halt(1);
        false -> ok
    end;
main(_) ->
    io:format(standard_error,"Usage: inspect_phi_protocol.escript PHI_APPLICATION FRESH_OUTPUT~n",[]),
    halt(2).

%% Load freshly compiled source without changing installed or frozen beam files.
-spec load(file:filename(),list()) -> ok.
load(File,Options)->
    {ok,M,B}=compile:file(File,[binary,debug_info,warnings_as_errors,report|Options]),
    {module,M}=code:load_binary(M,File,B),ok.

%% Expand routes through the ordinary checked translator; retain original ingress contracts.
-spec inventory(string(),map(),map(),file:filename()) -> map().
inventory(Name,Topology,Plans,Output)->
    Normal=hls_topology:normalize(Topology),
    Expanded=#{actors:=Actors,routes:=FullRoutes}=hls_protocol_topology:elaborate(Normal,64),
    Used=maps:with(lists:usort([M||#{module:=M}<-Actors]),Plans),
    R=#{channels:=Channels,diagnostics:=Diagnostics,obligations:=Obligations}=hls_protocol_inventory:inspect(Expanded,Used),
    Stem=filename:join(Output,Name),
    ok=file:write_file(Stem++".etf",term_to_binary(#{normalized=>Normal,topology=>Expanded,modules=>Used,inventory=>R},[deterministic]),[exclusive]),
    ok=file:write_file(Stem++".txt",io_lib:format("~tp.~n",[#{boundaries=>maps:get(boundaries,R),diagnostics=>Diagnostics,channels=>Channels}]),[exclusive]),
    Pairs=lists:usort([{S,D}||#{source:=S,destination:=D={actor,_}}<-Channels]),
    #{name=>list_to_binary(Name),actors=>length(Actors),routes=>length(FullRoutes),
      channel_classes=>length(Channels),sender_destination_pairs=>length(Pairs),
      repeated_pair_classes=>[#{sender=>text(S),destination=>text(D),channels=>length(Cs)}
          ||{S,D}<-Pairs,Cs<-[[C||C=#{source:=S0,destination:=D0}<-Channels,S0=:=S,D0=:=D]],length(Cs)>1],
      startup_messages=>lists:sum([length(Ms)||#{messages:=Ms}<-maps:get(startup,Expanded)]),
      source_diagnostics=>length(Diagnostics),unresolved_obligations=>length(Obligations),
      ingress_contract=>text(maps:get(ingresses,Expanded)),eligible=>false}.

%% Report complete ordinary source shapes, including branchy entries and asynchronous control.
-spec source_summary(map()) -> map().
source_summary(#{program:=Program})->
    S=xls_actor_program:spec(Program),P=xls_actor_program:plan(Program),
    #{source:=File,source_sha256:=Hash}=xls_statem_plan:provenance(P),
    #{source=>list_to_binary(File),source_plan_sha256=>binary:encode_hex(Hash,lowercase),
      phases=>maps:get(phases,S),message_words=>maps:get(message_words,S),messages=>maps:get(message_names,S),
      outputs=>maps:get(output_names,S),callbacks=>length(xls_statem_plan:callbacks(P)),
      entries=>length(maps:get(entries,S)),retained_calls=>text(maps:get(retained_calls,S)),
      continuations=>text(maps:get(continuations,S)),
      gathers=>text(maps:get(gathers,S)),reductions=>text(maps:get(reductions,S))}.

%% Artifact identities are exact bytes, not proof claims about the compiler.
-spec digest(file:filename()) -> binary().
digest(Path)->{ok,B}=file:read_file(Path),binary:encode_hex(crypto:hash(sha256,B),lowercase).

%% Text is display-only; the ETF retains the complete source structures.
-spec text(term()) -> binary().
text(T)->unicode:characters_to_binary(io_lib:format("~tp",[T])).
