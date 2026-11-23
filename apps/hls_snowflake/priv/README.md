# Installed Snowflake evidence inputs

[fixtures](fixtures/README.md) contains the compact, fixed reference inputs consumed by application tests through `code:priv_dir(hls_snowflake)`. Packaging keeps these inputs with their application, independently of the checkout location.

Reference generators and pinned optional Python dependencies live in [reference](../reference/README.md). Generated hardware, simulation output and measurement reports belong in build stages or the external artifact archive, not this installed input directory.
