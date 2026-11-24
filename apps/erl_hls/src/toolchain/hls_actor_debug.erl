-module(hls_actor_debug).
-moduledoc """
Source-aware actor debug orchestration for the erl_hls facade.

The compiler validates retained projections, then the runtime binds their
manifest resources to logical observation handles. Deployed consumers can bind
an already validated projection through hls_debug_catalog without loading
compiler code.
""".

%% Source-aware runtime catalog construction.
-export([catalog/3]).

-doc """
Validates a dedicated actor projection against current source facts, then binds
its retained manifest resources to the logical runtime catalog.
""".
-spec catalog(hls_topology:plan(), [{boundary, pid(), term()}], map()) -> map().
catalog(Plan, Boundaries, Session = #{manifest := Manifest}) ->
    Projection = maps:get(<<"actor_projection">>, Manifest, none),
    ok = xls_actor_debug:validate(Plan, Projection),
    Catalog = hls_debug_catalog:hardware(Plan, #{}, Boundaries),
    hls_debug_catalog:bind(Catalog, Projection, Session).
