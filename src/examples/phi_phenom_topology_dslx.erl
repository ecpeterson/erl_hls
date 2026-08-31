%%%% phi_phenom_topology_dslx
%%%%
%%%% Physical DSLX profile for the closed phi/noise experiment.

-module(phi_phenom_topology_dslx).
-moduledoc """
Generates the current closed phi/noise DSLX fixture.

The generator validates route schema membership and actor-to-actor layouts
from compiler-emitted interfaces. Its direct Frame transport also requires
equal local selectors, while producers sharing an external output must agree
on one selector and layout. This profile contains only physical choices which
are not actor facts. Its current mux trees may reorder messages sent through
different ports of one actor to one destination.
`aliased_port_order => may_reorder` accepts that limitation for this fixture.
The generator derives and reports the affected lanes from
`phi_phenom_topology:topology/0`; this profile does not restate them or claim
unverified application properties.
""".

-export([profile/0, to_dslx/0]).

-doc "Returns the version-0 physical profile for the DSLX fixture.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        version => 0,
        name => phi_phenom_topology,
        channel_depth => 1,
        aliased_port_order => may_reorder
    }.

-doc "Generates the DSLX source for the closed phi/noise fixture.".
-spec to_dslx() -> iolist().
to_dslx() ->
    xls_topology_dslx:from_module(phi_phenom_topology, profile()).
