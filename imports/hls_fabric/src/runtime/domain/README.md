# Hardware-domain endpoints

`hls_domain_fabric` implements the runtime library's `hls_domain_backend` contract over independent, deployment-owned management and application brokers. It consumes an emitted interface and retained record codecs; it does not compile sources or infer application recovery policy. `hls_domain_endpoint` gives each ready actor incarnation an ordinary monitored ERTS endpoint, usable directly or through the [distribution node](../node/README.md).

The generated bridge supplies incarnation admission, response sequencing and the accepted-output frontier. The backend waits for that frontier before orderly actor retirement. Broker loss, invalid framing and an incomplete frontier terminate local endpoints with connection uncertainty. Neither a backend restart nor an owner monitor certifies physical reset or releases external resources. Deployment code remains responsible for exclusive transport attachment and actual device retirement.

[Wire codecs](../../wire/README.md) contain `hls_domain_wire`, which uses the same retained actor schemas for calls, replies and effects. Typed application messages and current-call ownership remain separate from the lifecycle controller's one retained management transition.
