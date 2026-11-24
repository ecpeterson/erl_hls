# Installed Phi hardware assets

[rtl](rtl/README.md) contains application shell templates loaded by Phi generators through `code:priv_dir(hls_phi)`. They compose decoder-specific interfaces; generic FIFO, routing and storage support remains with `hls_target`, and physical board integration remains under [platforms](../../../platforms/xc7/README.md).

Type-provider DSLX companions stay beside their owning modules in [src](../src/README.md), where source staging resolves them. Testbenches and diagnostic VPI helpers live in [test/rtl](../test/rtl/README.md). Generated artifacts belong in fresh build stages rather than this asset directory.
