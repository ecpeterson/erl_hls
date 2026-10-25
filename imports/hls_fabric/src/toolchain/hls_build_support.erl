-module(hls_build_support).
-moduledoc "Shared support-tree layout for both fabric hardware backends.".
-export([layout/1]).

-doc "Resolves compiler, fabric and caller import trees for inspection and source packaging. Paths are copied only when the builder writes its bundle; no XLS tool is needed.".
-spec layout([file:filename()]) ->
    #{libraries := [hls_artifact_bundle:library()], imports := [string()]}.
layout(Imports) ->
    #{libraries := CompilerLibraries, imports := CompilerImports} = hls_compile:support_layout(Imports),
    Fabric = code:priv_dir(hls_fabric),
    Libraries = [{filename:join(Fabric, "xls"), "support/fabric/xls", [".x"]},
        {filename:join(Fabric, "rtl"), "support/fabric/rtl", [".v", ".sv"]}],
    Paths = ["lib", "fabric"],
    #{libraries => Libraries ++ CompilerLibraries,
      imports => ["support/fabric/xls/" ++ P || P <- Paths,
          filelib:is_dir(filename:join([Fabric, "xls", P]))] ++
          [unicode:characters_to_list(P) || P <- CompilerImports]}.

