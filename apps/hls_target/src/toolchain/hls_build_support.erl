-module(hls_build_support).
-moduledoc """
Compiler, communication and target support-tree layout shared by source and scheduler bundle orchestration. Builders copy these trees only when publishing a bundle.
""".
%% Installed and caller-owned support layout.
-export([layout/1]).

-doc "Resolves compiler, fabric and caller import trees for inspection and source packaging. Paths are copied only when the builder writes its bundle; no XLS tool is needed.".
-spec layout([file:filename()]) ->
    #{libraries := [hls_artifact_bundle:library()], imports := [string()]}.
layout(Imports) ->
    #{libraries := CompilerLibraries, imports := CompilerImports} = hls_compile_support:layout(
        Imports
    ),
    Fabric = code:priv_dir(hls_fabric),
    Target = code:priv_dir(hls_target),
    Libraries = [
        {filename:join(Fabric, "xls"), "support/fabric/xls", [".x"]},
        {filename:join(Fabric, "rtl"), "support/fabric/rtl", [".v", ".sv"]},
        {filename:join(Target, "xls"), "support/target/xls", [".x"]},
        {filename:join(Target, "rtl"), "support/target/rtl", [".v", ".sv"]}
    ],
    FabricPaths = ["fabric"],
    TargetPaths = ["lib"],
    #{
        libraries => Libraries ++ CompilerLibraries,
        imports => [
            "support/fabric/xls/" ++ P
         || P <- FabricPaths,
            filelib:is_dir(filename:join([Fabric, "xls", P]))
        ] ++
            [
                "support/target/xls/" ++ P
             || P <- TargetPaths,
                filelib:is_dir(filename:join([Target, "xls", P]))
            ] ++
            [unicode:characters_to_list(P) || P <- CompilerImports]
    }.
