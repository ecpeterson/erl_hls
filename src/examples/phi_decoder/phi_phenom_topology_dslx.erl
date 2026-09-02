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
are not actor facts. Actor actions leave through one source-ordered stream;
the topology router assigns one queue to each source/recipient lane before
different sources are arbitrated at a destination.
""".

-export([profile/0, to_dslx/0]).

-doc "Returns the physical profile for the DSLX fixture.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        name => phi_phenom_topology,
        channel_depth => 1,
        actor_egress_depth => burst
    }.

-doc "Generates the DSLX source for the closed phi/noise fixture.".
-spec to_dslx() -> iolist().
to_dslx() ->
    xls_topology_dslx:from_module(phi_phenom_topology, profile()).
