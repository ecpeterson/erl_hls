-module(hls_protocol_partition_tests).
-moduledoc "Partition selection and unsupported outer boundaries fail before hardware emission.".
-include_lib("eunit/include/eunit.hrl").

%% Unknown, duplicate, empty, full and untyped selections cannot silently change ownership.
-spec selection_test() -> ok.
selection_test() ->
    Bundle=#{topology=>#{actors=>[#{id=>a},#{id=>b},#{id=>c}]}},
    Fabric=#{sources=>[#{index=>0},#{index=>1},#{index=>2}],links=>[],boundaries=>[]},
    lists:foreach(fun(Ids)->?assertError({invalid_native_actors,Ids},
        hls_protocol_partition:plan(#{native_actors=>Ids},Bundle,#{},Fabric,none)) end,
        [[],[a,a],[unknown],[a,b,c],all]),
    #{fabric:=Fabric,indices:=[0,1,2]}=hls_protocol_partition:plan(#{},Bundle,#{},Fabric,none),
    Ingress=#{actors=>3,targets=>[#{recipients=>[#{index=>0},#{index=>1},#{index=>2}]}]},
    #{fabric:=#{sources:=[#{index:=0},#{index:=2}]},indices:=[0,2],
        ingress:=#{actors:=3,targets:=[#{recipients:=[#{index:=0},#{index:=2}]}]}}=
        hls_protocol_partition:plan(#{native_actors=>[c,a]},Bundle,#{},Fabric,Ingress),ok.

%% Unsupported framed application and inspection paths cannot drop crossing pins.
-spec unsupported_outer_boundary_test() -> ok.
unsupported_outer_boundary_test() ->
    ?assertError(partition_inspection_unavailable,hls_protocol_network:write(#{native_actors=>[a],inspection=>process},"unused")),
    ?assertError(partition_application_gateway_unavailable,hls_protocol_application:write(#{native_actors=>[a],device=>board,host=>1},"unused")).
