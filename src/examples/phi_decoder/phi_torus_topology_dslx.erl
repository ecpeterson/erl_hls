%%%% phi_torus_topology_dslx
%%%%
%%%% Physical DSLX profile for the compact phi torus witness.

-module(phi_torus_topology_dslx).
-moduledoc """
Generates the compact regular phi-torus DSLX fixture.

The semantic topology remains a family and five route rules. The backend uses
channel arrays and nested `unroll_for!` spawns, so this module does not choose
or enumerate actor-instance names. The scalar syndrome-request boundary is a
fair polling merge over the bounded family lanes.
""".

-export([profile/0, to_dslx/0]).

-doc "Returns the physical profile for the torus fixture.".
-spec profile() -> xls_topology_dslx:profile().
profile() ->
    #{
        name => phi_torus_topology,
        channel_depth => 1
    }.

-doc "Generates DSLX for the compact default torus plan.".
-spec to_dslx() -> iolist().
to_dslx() ->
    xls_topology_dslx:from_module(phi_torus_topology, profile()).
