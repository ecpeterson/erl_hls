%% Small RTL fixture for the production router and its buffered ownership protocol.
-module(xls_effect_router_testgen).
-moduledoc "Generates ordinary and captured-prefix routers for the effect-window RTL regression.".
-export([write/2]).

-doc "Writes an isolated production router with ordinary multicast or captured-prefix routing.".
-spec write(string(), string()) -> ok.
write(Mode, Output) when Mode =:= "ordinary"; Mode =:= "prefix" ->
    Prefix = Mode =:= "prefix",
    PortRoutes = [#{source => {probe, report}, delivery => queued,
        recipients => [{external, left}, {external, right}]}] ++
        case Prefix of
            true -> [];
            false -> [#{source => {probe, north}, delivery => direct,
                        recipients => [{external, left}]},
                      #{source => {probe, south}, delivery => direct,
                        recipients => [{external, right}]}]
        end,
    Family = #{id => probe, module_name => "router_probe_actor",
        outputs => [north, south, report], routes => PortRoutes,
        source_fragment_ports => case Prefix of true -> [north, south]; false -> [] end},
    Fragments = [#{ordinal => 0, port => north, inverse_offset => [0,1], inverse_ordinal => 1},
                 #{ordinal => 1, port => south, inverse_offset => [0,-1], inverse_ordinal => 0}],
    Plane = #{id => probe, module_name => "router_probe_actor", population => 2,
        fragments => Fragments, shape => [1,1], source_schedulers => [0]},
    Planes = case Prefix of true -> [Plane]; false -> [] end,
    Spec = #{effect_window_domains => [#{}], source_fragment_planes => Planes,
        externals => [#{id => left, output_name => "left_out"},
                      #{id => right, output_name => "right_out"}]},
    Scheduler = #{index => 0, stem => "probe", module_name => "router_probe_actor",
        families => [Family], destinations => [], external_ids => [left, right]},
    Header = "// Production-generated router; only the fixture ABI and boundary wrapper are handwritten.\n"
        "import axis;\nimport effect_window;\nimport router_probe_actor;\n"
        "// One fixture family owns both destination lanes.\n"
        "enum FamilyId : u1 { PROBE = 0 }\n"
        "// A single slot always selects the fixture family at the origin.\n"
        "struct Address { family: FamilyId, x: u16, y: u16 }\n"
        "// All scheduled slot values map to the sole fixture source.\n"
        "fn probe_address(_slot: u32) -> Address { zero!<Address>() }\n",
    Declaration = case Prefix of
        true -> apply(xls_topology_source_fragment_dslx, fragment_declarations, [Plane]);
        false -> []
    end,
    %% The runner loads test-local export_all builds; production exports stay unchanged.
    Router = apply(xls_topology_scheduler_dslx, router_proc, [Spec, Scheduler]),
    PrefixArg = case Prefix of true -> "      prefix_out: chan<ProbeReductionBatch> out,\n"; false -> "" end,
    PrefixName = case Prefix of true -> "prefix_out, "; false -> "" end,
    {ok, Template} = file:read_file("test/rtl/effect_router_top.x.in"),
    Wrapper = binary:replace(binary:replace(Template,
        <<"@@PREFIX_ARG@@">>, list_to_binary(PrefixArg)),
        <<"@@PREFIX_NAME@@">>, list_to_binary(PrefixName)),
    ok = file:write_file(Output, [Header, Declaration, Router, Wrapper]).
