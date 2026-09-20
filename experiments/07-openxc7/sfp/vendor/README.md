# Trenz RGPIO reference

`ddsrpi_slave.vhd` is the unmodified slave from Trenz's `rgpio_1.0.zip`; `source.json` pins its archive, member and generated-Verilog hashes. Trenz [licenses this core under MIT](https://wiki.trenz-electronic.de/display/PD/RGPIO). `ddsrpi_slave.v` is GHDL's Verilog translation, retained so Icarus tests need no VHDL tool or network. These files are test references, not part of the FPGA image.

From the repository root, regenerate with GHDL 6.0.0-dev from the pinned OSS CAD Suite, or pass `--ghdl` to `test_sfp_probe.py` to check exact reproduction:

```sh
ghdl synth --std=08 --out=verilog experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd -e ddsrpi_slave > experiments/07-openxc7/sfp/vendor/ddsrpi_slave.v
```

The vendor's unused `user_clk` output has no assignment; its warning is expected. The native bundle's GHDL needs duplicate `LC_RPATH` entries removed from a local executable copy on this macOS release; the installed toolchain is unchanged.
