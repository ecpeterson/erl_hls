-module(hls_compile_boundary_tests).
-moduledoc "Exercises computation synthesis without Fabric, target or spacetime applications.".

-include_lib("eunit/include/eunit.hrl").

%% Source analysis and XLS computation lowering stop at the compiler artifact boundary.
-spec computation_only_lowering_test() -> ok.
computation_only_lowering_test() ->
    Artifact = xls_parse:to_artifact(
        "apps/hls_compile/test/hls_compile_boundary_fixture.erl", #{}
    ),
    Source = xls_emitted:bytes(Artifact),
    ?assertNotEqual(nomatch, binary:match(Source, <<"pub proc Top">>)),
    ?assertNotEqual(nomatch, binary:match(Source, <<"struct ActorState">>)).
