-module(hls_actor_identity).
-moduledoc "Stable encoding of logical actor identities for emitted observation manifests and live catalog lookup. Both sides hash the same deterministic Erlang term; this identifies a logical actor, not an incarnation or source revision.".
%% Shared observation identity.
-export([actor_key/1]).

-doc "Encodes a logical actor identity deterministically for catalog lookup.".
-spec actor_key(term()) -> binary().
actor_key(Id) -> digest(Id).

%% Fingerprints a deterministic serialization of logical identity or build metadata.
-spec digest(term()) -> binary().
digest(Term) ->
    string:lowercase(
        binary:encode_hex(
            crypto:hash(
                sha256,
                term_to_binary(Term, [deterministic])
            )
        )
    ).
