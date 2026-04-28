# xls

## Use

Build with these steps:

```sh
./ir_converter_main --top=Top xls_regsvc.x > xls_regsvc.ir
./opt_main xls_regsvc.ir > xls_regsvc.opt.ir
./codegen_main --pipeline_stages=1 --delay_model=unit --use_system_verilog=false --reset=reset xls_regsvc.opt.ir --fifo_module= > xls_regsvc.v
```

Then, import the generated `xls_regsvc.v` alongside the static `xls_regsvc_wrapper.v` (which segments the message bus into TDATA, TLAST, etc., and adds Vivado port annotations).

To add the module, use the Tcl command `create_bd_cell -type module -reference axis_regsvc_xls_axis_wrapper axis_regsvc_xls_axis_wrapper`.  It wouldn't let me drag-and-drop; I don't know why.

## Notes

+ Without `--fifo_module`, it will still compile, but it leaves in a reference to [some SystemVerilog in the XLS standard library](https://github.com/google/xls/blob/main/xls/modules/zstd/rtl/xls_fifo_wrapper.sv), which has to be exported to Vivado alongside the codegen'd Verilog.  It is probably preferable to figure out how to use these provided modules, especially since the other file in the same directory says it provides a crossbar for multiple access...
+ Doesn't yet handle `bulk_get`, essentially because our AXIS wrapper requires a (max-packet-width)-wide output bus.
+ Needs a lot of clean-up!
