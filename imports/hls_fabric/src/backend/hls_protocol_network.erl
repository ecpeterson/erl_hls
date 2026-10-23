-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport with declared startup messages. Host commands enter ordinary inbox slots; application admission remains separate.".
-export([write/2]).

-doc "Builds a complete sampled-clock network from the same trusted fresh-source config as hls_protocol_transport:write/2. Connects whole entry batches, capture selection and delayed release using the existing component state. Delivers declared startup records and a checked rectangular host ingress through the ordinary inbox. Host admission waits for startup consumption; each pending recipient retires only on source consume. A malformed accepted command latches ingress_fault until reset. External outputs remain separate ready/valid streams; they have no cross-source order. Returns the generated network manifest, with capacity/progress eligibility false. Requires a fresh directory; failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config,Output) ->
    Plan = hls_protocol_transport:write(Config,Output),
    xls_protocol_network:write(Plan,Output).
