# Fabric build library

`hls_lowering` owns topology planning, hardware lowering, build frontends, the tiny counter build walkthrough and the DSLX/RTL support assets under `priv/`. It consumes compiler APIs from `erl_hls` and retained runtime descriptors from `hls_fabric`; the runtime cannot depend on this application.

`rebar3 release -n hls` packages the build CLI with its compiler and source assets. `rebar3 release -n hls_fabric` packages only the virtual-node runtime and its runtime libraries. This library has no application callback or supervisor; starting a fabric node is an explicit runtime operation.
