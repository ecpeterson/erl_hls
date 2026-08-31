%%%% phi_phenom_topology_dslx
%%%%
%%%% Physical DSLX profile for the closed phi/noise experiment.

-module(phi_phenom_topology_dslx).
-moduledoc """
Generates the current closed phi/noise DSLX fixture.

This physical profile makes the experiment's temporary backend assumptions
explicit. The three actor artifacts share one public tag codebook and route
interfaces are assumed compatible while actor interface summaries are still
incomplete; the generator does not yet check that assumption.
Its current mux trees may reorder messages sent through different ports of one
actor to one destination. `aliased_port_order => may_reorder` accepts that
limitation for this fixture. The generator derives and reports the affected
lanes from `phi_phenom_topology:topology/0`; this profile does not restate them
or claim unverified application properties.
""".

-export([profile/0, to_dslx/0]).

-doc "Returns the version-0 physical profile for the DSLX fixture.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        version => 0,
        name => phi_phenom_topology,
        channel_depth => 1,
        route_interfaces => assumed_compatible,
        codebook => shared,
        aliased_port_order => may_reorder
    }.

-doc "Generates the DSLX source for the closed phi/noise fixture.".
-spec to_dslx() -> iolist().
to_dslx() ->
    xls_topology_dslx:from_module(phi_phenom_topology, profile()).
