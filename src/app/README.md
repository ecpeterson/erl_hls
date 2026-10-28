# OTP application bootstrap

`erl_hls.app.src` selects `erl_hls_app`, which starts `erl_hls_sup`. The supervisor currently has no children. Compilation is invoked through `hls_compile`/`hls_compile_cli`, and runtime clients start their own sessions; starting the OTP application does not launch a compiler worker or connect hardware.

This directory contains only the `application` and `supervisor` callbacks. It is not the public HLS language API, which lives in [api](../api/README.md). Changes to application packaging or permanent process ownership should be explicit rather than hidden in compilation helpers.
