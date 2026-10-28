# DSLX documents and finalization

Expression lowerers, type providers and wiring generators build `xls_dslx` nodes and deferred fragments. `xls_names` owns target identifier spelling and collision checks; `xls_dslx_imports` derives declared imports from prepared source and its providers.

`xls_failure_sites` connects source locations to structured failure references. `xls_emitted` allocates the references retained in a complete document and renders the final DSLX bytes with their codebook. `xls_parse_io` supplies terminal text indentation; fragments containing failure references must use deferred `xls_dslx:indent/2` until finalization.

This target document is distinct from [source evaluation state](../expressions/README.md), [actor semantic contracts](../actors/README.md) and the external XLS typed optimization IR. Filesystem packaging and external tool invocation belong to the compiler [toolchain](../../../toolchain/README.md).
