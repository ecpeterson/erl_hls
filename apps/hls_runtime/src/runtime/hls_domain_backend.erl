-module(hls_domain_backend).
-moduledoc """
Host adapter boundary between a deployment owner and a finite domain controller.

An attachment is exclusive and does not reset application actors. Commands carry
expected-old/target identities; only a backend establishes fence, reset and setup
completion. An unavailable transport returns an error, never synthetic readiness.
Endpoint PIDs represent one incarnation and must be retired rather than rebound.
""".

%% Shared host-side evidence and control-session capability.
-export_type([authority/0, actors/0, snapshot/0]).

-doc "An opaque local control-session token held only by its attached owner.".
-type authority() :: reference().
-doc "Deployment-local actor identities and their incarnation-specific host endpoints.".
-type actors() :: #{term() => pid()}.
-doc "Observed controller state and first backend failure detail; non-ready actor identities are private diagnostics, not admitted endpoints. Reset count is optional instrumentation.".
-type snapshot() :: #{
    state := hls_domain_lifecycle:state(),
    actors := actors(),
    fault_reason := term(),
    reset_count => non_neg_integer()
}.

-doc "Attaches a local owner without changing lifecycle state; another live owner is rejected.".
-callback attach(pid(), pid()) -> {ok, authority()} | {error, term()}.

-doc "Reads controller evidence, including incomplete or failed transitions, without inventing completion.".
-callback status(pid()) -> {ok, snapshot()} | {error, term()}.

-doc "Submits an authorized lifecycle command. The backend alone generates physical completion acknowledgements and faults.".
-callback request(pid(), authority(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.

-doc "Resolves an actor only if authority, nonzero incarnation and readiness agree at this boundary.".
-callback endpoint(pid(), authority(), hls_nums:u64(), term()) -> {ok, pid()} | {error, term()}.
