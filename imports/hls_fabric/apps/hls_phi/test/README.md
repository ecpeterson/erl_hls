# Phi witnesses

These fixtures exercise the application actors, noise/correction loop, geometry, source-protocol placement and scheduler composition. Compiler-era whole-application interface/topology tests are retained here with `phi_source_` names; the compiler repository now exercises those APIs with small local semantic fixtures. EUnit runs without XLS. RTL benches and external-tool drivers exercise finite workloads separately and do not claim unrestricted correctness or physical-device operation.
