XLS modules cribbed from their examples.  Bridge mostly built by ChatGPT.

Needs: Icarus Verilog, cc (eg: gcc), XLS (eg: https://github.com/google/xls?tab=readme-ov-file#install-latest-release).

Build:
```sh
./ir_converter_main --top=fp32_fmac fp32_fmac.x > fp32_fmac.ir
./opt_main fp32_fmac.ir > fp32_fmac.opt.ir
./codegen_main --pipeline_stages=2 --delay_model=unit --use_system_verilog=false --reset=reset fp32_fmac.opt.ir > fp32_fmac.v

iverilog -o sim.vvp -g2005-sv tb.v fp32_fmac.v

iverilog-vpi bridge.c
```

Simulate design:
```sh
vvp -M. -m bridge sim.vvp  # to close: C-c finish RET
```

Communicate with design via Python (separate terminal):
```sh
python3 python.py
```

Communicate with design via Erlang (separate terminal):
```sh
erlc *.erl
1> demo:main(fp32_fmac).  % Erlang-native fmac
2> demo:main(erl).        % Icarus bridge
```
