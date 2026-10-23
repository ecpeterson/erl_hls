-module(hls_protocol_inspection_shapes).
-moduledoc "Fresh plain, scalar and indexed-gather observation declarations for typed-machine cross checks.".
-export([write/2]).

-doc "Emits each ordinary actor and its source-bound observation into a fresh fixture directory. These compiler shape fixtures do not claim a connected application or admission.".
-spec write(file:filename(),file:filename()) -> ok.
write(Compiler,Stage) ->
    ok=file:make_dir(Stage),
    Cases=[{plain,"test/hls_local_actor_fixture.erl"},
        {scalar,filename:join(Compiler,"test_data/hls_statem_reduction_lower_fixture.erl")},
        {gather,filename:join(Compiler,"test_data/xls_statem_gather_fixture.erl")}],
    lists:foreach(fun({Name,File})->
        A=hls_local_actor:compile(File,[]),Directory=filename:join(Stage,atom_to_list(Name)),ok=file:make_dir(Directory),
        Manifest=hls_local_actor:write(A,filename:join(Directory,"actor.x")),
        _=hls_protocol_inspection:write(#{bundle=>#{topology=>#{actors=>[#{id=>Name,module=>Name}]},modules=>#{Name=>A}},
            receivers=>[#{index=>0,module=>Name,manifest=>Manifest}]},Directory)
    end,Cases),ok.
