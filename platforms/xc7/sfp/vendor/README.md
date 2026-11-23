# Trenz RGPIO reference

`ddsrpi_slave.vhd` is the unmodified slave from Trenz's `rgpio_1.0.zip`; `source.json` pins its archive, member and generated-Verilog hashes. Trenz [licenses this core under MIT](https://wiki.trenz-electronic.de/display/PD/RGPIO). `ddsrpi_slave.v` is GHDL's Verilog translation, retained so Icarus tests need no VHDL tool or network. These files are test references, not part of the FPGA image.

From the repository root, use GHDL 6.0.0-dev from the pinned OSS CAD Suite to check exact reproduction:

```sh
python3 platforms/xc7/test_sfp_probe.py --ghdl /path/to/ghdl
```

The checker stages the VHDL under its original source name in a temporary directory because GHDL embeds that name in generated comments. It compares the complete output with the pinned Verilog without rewriting either the reference or its hash.

The vendor's unused `user_clk` output has no assignment; its warning is expected. The native bundle's GHDL needs duplicate `LC_RPATH` entries removed from a local executable copy on this macOS release; the installed toolchain is unchanged.
