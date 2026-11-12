-module(hls_protocol_domains_fixture).
-moduledoc "Counts trusted topology elaborations without changing the real source actors or their hardware behavior.".

%% Source-topology callback loaded alongside the actor sources.
-export([topology/1]).

-doc "Records one constructor call in the caller's process dictionary, then returns the ordinary three-actor fixture topology. The test initializes the counter before source preparation.".
-spec topology(term()) -> map().
topology(Key) ->
    Count = get(Key),
    put(Key, Count + 1),
    hls_cross_domain_producer:topology().
