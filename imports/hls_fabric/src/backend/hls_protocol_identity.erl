-module(hls_protocol_identity).
-moduledoc "Canonical source and emitted-boundary identities for protocol attachment. Diagnostic provenance and downstream tool outputs remain separate.".
-export([source_modules/1, boundary/2]).

-doc "Returns versioned compiler content identities for freshly compiled actor modules. Keeps complete source and lowering distinctions, including origin sharing, without build-local references or checkout paths. This does not validate saved or edited artifacts; use only the unchanged source bundle from transport preparation.".
-spec source_modules(#{module() => hls_local_actor:source() | hls_local_actor:artifact()}) -> map().
source_modules(Modules) ->
    maps:map(fun(_, #{program := Program}) ->
        xls_statem_plan:identity(xls_actor_program:plan(Program)) end, Modules).

-doc "Binds an unchanged transport plan to its emitted boundary files. Covers normalized topology, native placement, arithmetic groups, compiler content identities and exact generated DSLX/Verilog bytes. Excludes report/ETF provenance and optional model analysis. Relative output names are significant; output directories are not. Imported support files and downstream XLS/RTL tools belong to the enclosing package, not this boundary identity. Call after boundary emission, before inserting the attachment identity into its gateway.".
-spec boundary(map(), hls_generated_files:files()) -> map().
boundary(#{bundle := #{topology := Topology, modules := Modules},
        arithmetic := Arithmetic, fabric := #{sources := Native}}, Files) ->
    #{version => 1, topology => Topology, source_modules => source_modules(Modules),
      native_indices => [I || #{index := I} <- Native], arithmetic => Arithmetic,
      hardware => [#{file => list_to_binary(File), sha256 => hls_generated_files:hash(Bytes)}
          || {File, Bytes} <- lists:sort(maps:to_list(Files)), hardware(File)]}.

%% Report paths, source contexts and optional model results never enter generated hardware.
-spec hardware(string()) -> boolean().
hardware(File) -> lists:member(filename:extension(File), [".x", ".sv"]).
