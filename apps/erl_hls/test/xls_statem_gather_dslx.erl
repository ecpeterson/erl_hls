-module(xls_statem_gather_dslx).
-moduledoc "Writes generic indexed gather witnesses for the XLS interpreter and JIT.".
-export([write/1]).

-doc "Emits the mixed gather/scalar ordinary actor and its bounded semantic witnesses.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Actor = xls_parse:to_xls("test_data/xls_statem_gather_fixture.erl"),
    {ok, Tests} = file:read_file("test_data/xls_statem_gather_semantics.inc.x"),
    ok = file:write_file(filename:join(Stage, "statem_gather.x"), [Actor, Tests]),
    Sites = xls_parse:to_xls("test_data/xls_statem_gather_sites_fixture.erl"),
    {ok, SiteTests} = file:read_file("test_data/xls_statem_gather_sites_semantics.inc.x"),
    ok = file:write_file(filename:join(Stage, "statem_gather_sites.x"), [Sites, SiteTests]),
    Debug = xls_parse:to_xls("test_data/xls_statem_gather_fixture.erl", #{direct_actor_debug => true}),
    {ok, DebugTests} = file:read_file("test_data/xls_statem_gather_debug_semantics.inc.x"),
    file:write_file(filename:join(Stage, "statem_gather_debug.x"), [Debug, DebugTests]).
