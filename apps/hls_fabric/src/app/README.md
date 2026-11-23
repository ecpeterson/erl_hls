# Application lifecycle

`hls_fabric_app` starts `hls_fabric_sup`, the supervisor under which callers explicitly create virtual device nodes. This is the OTP application boundary; loading the compiler or emitting a hardware bundle does not start a node or attach hardware.

The supervisor delegates each configured node to [runtime/node](../runtime/node/README.md). Physical brokers are supplied by the deployment owner, so application startup does not open device descriptors, reset hardware or select a bitstream. Generic transport processes and compilation do not belong in this directory.
