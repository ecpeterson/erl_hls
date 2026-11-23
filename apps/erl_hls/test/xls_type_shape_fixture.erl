-module(xls_type_shape_fixture).
-export([with_source/1, load/2]).

with_source(Test) ->
    Directory = filename:absname(filename:join("_build",
        "type-shapes-" ++ integer_to_list(erlang:unique_integer([positive])))),
    Actor = filename:join(Directory, "hls_shape_reduction_fixture.erl"),
    Provider = filename:join(Directory, "hls_shape_type_fixture.erl"),
    Header = filename:join(Directory, "hls_shape_type_config.hrl"),
    ok = filelib:ensure_dir(Actor),
    {ok, Source} = file:read_file("test_data/hls_list_reduction_fixture.erl"),
    Renamed = binary:replace(Source, <<"hls_list_reduction_fixture">>,
        <<"hls_shape_reduction_fixture">>),
    ok = file:write_file(Actor, binary:replace(Renamed,
        <<"hls_vec:vector(hls_nums:u32(), 2)">>,
        <<"hls_shape_type_fixture:vector()">>, [global])),
    {ok, _} = file:copy("test_data/hls_shape_type_fixture.erl", Provider),
    {ok, _} = file:copy("test_data/hls_shape_type_config.hrl", Header),
    try Test(Actor, Provider, Header)
    after
        [begin code:purge(M), code:delete(M) end
            || M <- [hls_shape_reduction_fixture, hls_shape_type_fixture]],
        ok = file:del_dir_r(Directory)
    end.

load(Path, Options) ->
    {ok, Module, Beam} = compile:file(Path, [binary, debug_info, report_errors | Options]),
    code:purge(Module),
    code:delete(Module),
    {module, Module} = code:load_binary(Module, Path, Beam),
    ok.
