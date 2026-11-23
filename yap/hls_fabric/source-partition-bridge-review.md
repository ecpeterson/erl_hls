# Source partition bridge review

This review is closed. The sole active task list is `Notes/erl_xls/Roadmap.md`; G3 owns any newly selected routing work and P6 owns physical deployment; the [original review](https://github.com/ecpeterson/hls_fabric/blob/28f8bd1562f7f429a8f482c4d73776b04cdc2e31/yap/source-partition-bridge-review.md) retains its initial scope.

- Replaced the two-board relay API with deployment-defined participants, actor-derived routes, endpoint bindings and retained-record limits.
- Separated application control decoding from bridge ownership and retained the two-role RTL and irregular three-role host witnesses.
- Completed the subsequent control-flow/ownership cleanup in [#123](https://github.com/ecpeterson/hls_fabric/pull/123) and [#141](https://github.com/ecpeterson/hls_fabric/pull/141).
- Completed frame-width parameterization in [#145](https://github.com/ecpeterson/hls_fabric/pull/145) and reduced integration coverage in [#121](https://github.com/ecpeterson/hls_fabric/pull/121).

The transport still has one physical writer and one common retirement/reset domain. General participant enumeration establishes no arbitrary-topology progress claim. The only application-control adapter is explicitly selected as `control => rectangle`. Return route pairs must be unique because the broker envelope has no sender-broker field. The newer [domain composition](../docs/domain-recovery.md) supplies a separate, explicitly selected incarnation boundary. It does not retrofit independent-reset, generation or delivery guarantees onto this legacy source-partition bridge. Composed conservation proofs and physical transport qualification remain separate from its finite witnesses.
