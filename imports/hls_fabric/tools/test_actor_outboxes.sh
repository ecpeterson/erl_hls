#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_actor_outboxes.sh XLS_ROOT [STAGE]}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$root/_build/actor-outboxes"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$root"
rebar3 as test compile
source tools/backend_env.sh test
erl -noshell \
    -eval 'ok = xls_actor_outbox_testgen:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$stage:$root/apps/hls_lowering/priv/xls/lib:$root/apps/hls_lowering/priv/xls/fabric:$erl_hls_root/priv/xls/lib:$erl_hls_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for module in mailbox scheduler; do
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$root/apps/hls_lowering/priv/xls/lib/$module.x"
done
source tools/scheduler_ram_configurations.sh
for kind in direct shared; do
    "$xls_root/ir_converter_main" --top=Top "${options[@]}" "$stage/outbox_$kind.x" > "$stage/$kind.ir"
    "$xls_root/opt_main" "$stage/$kind.ir" > "$stage/$kind.opt.ir"
    rams=""; schedules=(1 2); defines=(-DOUTBOX_FIXTURE)
    if [[ "$kind" == shared ]]; then rams=$(scheduler_ram_configurations 1); schedules=(2 3); defines=(-DSHARED_OUTBOX); fi
    for stages in "${schedules[@]}"; do
        "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
            --reset=reset --fifo_module= --module_name="outbox_$kind" --ram_configurations="$rams" \
            "$stage/$kind.opt.ir" > "$stage/${kind}_${stages}.v"
        iverilog -g2012 "${defines[@]}" -DOUTBOX_TOP="outbox_${kind}_wrapper" -s xls_actor_outbox_tb \
            -o "$stage/${kind}_${stages}.vvp" test/rtl/xls_actor_outbox_tb.sv \
            "$stage/outbox_${kind}_wrapper.v" "$stage/${kind}_${stages}.v" "$erl_hls_root"/priv/rtl/hls_1r1w_ram.v
        (cd "$stage" && vvp "${kind}_${stages}.vvp")
        "${YOSYS:-yosys}" -Q -T -p "read_verilog -sv $stage/outbox_${kind}_wrapper.v $stage/${kind}_${stages}.v $erl_hls_root/priv/rtl/hls_1r1w_ram.v; hierarchy -top outbox_${kind}_wrapper; proc; flatten; opt; scc -expect 0; check -assert" > "$stage/${kind}_${stages}.scc.log"
    done
done
