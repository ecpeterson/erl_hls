-module(phi_decoder_profile_build).
-moduledoc "One source build for decoder-profile actors, scheduler topology, RAM wrapper and observation metadata.".
-export([emit/2]).
-export_type([options/0]).

-doc "Observation and effect-window options for the fixed decoder profile; geometry, selected planes and shard count belong to phi_decoder_profile configuration.".
-type options() :: #{mailbox_debug => boolean(), direct_actor_debug => boolean(),
    effect_window_partition => global | weak_components}.

-doc "Returns generated relative files and the matching topology/profile/artifact requirements without writing output. Compiles each required actor once; wrapper, observation projection and RAM configuration reuse one retained generation plan and interface catalog. The input manifest hashes actor DSLX, topology DSLX, wrapper, geometry and the default compilation policy so an external compiler can reject changed bytes without parsing DSLX. Options may select observations or effect-window partitioning, not replace placement. Source/provider and template reads remain; no XLS or admission checks run.".
-spec emit(pos_integer() | map(), options()) -> hls_generated_files:output().
emit(ProfileOptions, Options) ->
    ok = options(Options),
    Config = #{planes := Planes} = phi_decoder_profile:normalize(ProfileOptions),
    Topology = hls_topology:normalize(phi_decoder_profile_topology:topology(Config)),
    Profile = maps:merge(phi_decoder_profile_topology_dslx:profile(Config), Options),
    Generation = xls_fabric_topology_dslx:plan(Topology, Profile),
    #{scheduler := Scheduler, interfaces := Interfaces,
        profile := #{frame_payload_words := Words}} = xls_fabric_topology_dslx:analysis(Generation),
    Requirements = xls_fabric_topology_dslx:artifact_requirements(Generation),
    ActorOptions = maps:with([mailbox_debug, direct_actor_debug], Options),
    Artifacts = maps:map(fun(Module, Requirement) ->
        Source = filename:join("src/examples/phi_decoder", atom_to_list(Module) ++ ".erl"),
        xls_scheduler_actor:to_artifact(Source, maps:merge(Requirement, ActorOptions))
    end, Requirements),
    Bindings = xls_scheduler_ram_v:bindings(Scheduler, hls_frame_layout:new(Words), Interfaces),
    ActorFiles = maps:from_list([{atom_to_list(Module) ++ ".x", xls_emitted:bytes(Artifact)}
        || {Module, Artifact} <- maps:to_list(Artifacts)]),
    Inputs = hls_generated_files:merge([ActorFiles, #{
        "phi_decoder_profile_topology.x" => xls_fabric_topology_dslx:emit(Generation),
        "phi_decoder_profile_top.v" => phi_decoder_profile_top_v:emit(Planes, Scheduler, Bindings, Options),
        "phi_decoder_profile.json" => json:encode(phi_decoder_profile:manifest(Config)),
        "phi_decoder_profile.build-profile.json" => json:encode(
            hls_diagnostic:json_value(hls_build_profile:experiment(#{})))}]),
    %% Experiment comparisons need a RAM recipe identity independent of actor count or source.
    Manifest = #{version => 1,
        ram_configuration => hls_generated_files:hash(term_to_binary(
            {xls_scheduler_ram_v:module_info(md5), xls_scheduler_ram_dslx:module_info(md5)})),
        inputs => maps:from_list([{unicode:characters_to_binary(Name), hls_generated_files:hash(Bytes)}
            || {Name, Bytes} <- maps:to_list(Inputs)]),
        ram_configurations => iolist_to_binary(xls_scheduler_ram_v:configurations(Bindings))},
    Files = hls_generated_files:merge([Inputs, #{
        "phi_decoder_profile.inputs.json" => json:encode(Manifest),
        "phi-actors.json" => json:encode(xls_scheduler_debug:projection(Generation, Artifacts))}]),
    #{files => Files, result => #{requirements => Requirements, topology => Topology,
        profile => Profile, artifacts => Artifacts}}.

%% Keep physical placement in the profile configuration and reject misspelled lowering options.
-spec options(options()) -> ok.
options(Options) ->
    case maps:keys(Options) -- [mailbox_debug, direct_actor_debug, effect_window_partition] of
        [] -> ok;
        Unknown -> error({unknown_profile_build_options, lists:sort(Unknown)})
    end.
