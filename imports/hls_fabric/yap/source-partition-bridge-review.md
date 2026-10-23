# Source partition bridge review

- [x] Replace the two-board relay API with a deployment-defined participant set, actor-derived routes, endpoint bindings and explicit retained-record limits.
- [x] Separate rectangle control decoding from bridge transport ownership; share framing and rectangle validation with the existing application gateway.
- [x] Retain the two-device real-broker/RTL witness and add three-device host-model coverage with irregular keys/endpoints, two destinations from one source, stalled completion and collective retirement.
- [ ] Keep parametric frame width, broader source/control-flow cleanup, and CI workload reduction in the existing post-campaign follow-on review.

The transport still has one physical writer and one common retirement/reset domain. General participant enumeration establishes no arbitrary-topology progress claim. The only current application-control adapter is explicitly selected as `control => rectangle`. Return route pairs must be unique because the broker envelope has no sender-broker field.
