# Application lifecycle

`hls_runtime_app` is the callback module for the `hls_runtime` application. It starts `hls_runtime_sup`, the supervisor under which callers explicitly create virtual device nodes. Loading synthesis applications or emitting a hardware bundle does not start a node or attach hardware.

The supervisor delegates each configured node to [runtime/node](../runtime/node/README.md). Physical brokers are supplied by the deployment owner, so application startup does not open device descriptors, reset hardware or select a bitstream. Generic transport processes and compilation do not belong in this directory.
