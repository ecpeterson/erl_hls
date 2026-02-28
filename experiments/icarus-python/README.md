XLS modules cribbed from their examples.  Bridge mostly built by ChatGPT.

Needs: Icarus Verilog, cc (eg: gcc), XLS (eg: https://github.com/google/xls?tab=readme-ov-file#install-latest-release).

Build:
```sh
export PATH=$PATH:/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64

ir_converter_main --dslx_stdlib_path=/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64/xls/dslx/stdlib --top=fp64_fmac fp64_fmac.x > _build/fp64_fmac.ir
opt_main _build/fp64_fmac.ir > _build/fp64_fmac.opt.ir
codegen_main --pipeline_stages=2 --delay_model=unit --use_system_verilog=false --reset=reset _build/fp64_fmac.opt.ir > _build/fp64_fmac.v

iverilog -o _build/sim.vvp -g2005-sv tb.v _build/fp64_fmac.v

iverilog-vpi bridge.c && mv bridge.o bridge.vpi _build
```

Simulate design:
```sh
vvp -M _build -m bridge _build/sim.vvp  # to close: C-c finish RET
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
