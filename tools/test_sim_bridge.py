#!/usr/bin/env python3
"""Exercise the real Icarus VPI bridge, including nonzero process failures."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "_build/sim_bridge"
STAGE.mkdir(parents=True, exist_ok=True)


def run(command, cwd, log):
    with log.open("w") as output:
        subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                       check=True, timeout=60)


def build_bridge(directory, fault=None):
    directory.mkdir(exist_ok=True)
    source = (ROOT / "test/rtl/xls_sim_bridge.c").read_text()
    if fault:
        args = "void *buf" if fault == "read" else "const void *buf"
        inject = f'''
static ssize_t fail_{fault}(int fd, {args}, size_t count) {{
    (void)fd; (void)buf; (void)count; errno = EIO; return -1;
}}
#define {fault} fail_{fault}
'''
        source = source.replace('#define BUFFER_SIZE', inject + '\n#define BUFFER_SIZE', 1)
    (directory / "xls_sim_bridge.c").write_text(source)
    shutil.copy(ROOT / "test/rtl/xls_sim_axis.h", directory)
    run(["iverilog-vpi", "xls_sim_bridge.c"], directory, directory / "build.log")


def fixture(body, missing=None, wide=None):
    declarations = []
    for prefix in ("s_axis", "m_axis", "s_dbg", "m_dbg"):
        for suffix, width, initial in (("tdata", 32, 0), ("tkeep", 4, 15),
                                       ("tlast", 1, 0), ("tvalid", 1, 0),
                                       ("tready", 1, 1)):
            name = f"{prefix}_{suffix}"
            if name == missing:
                continue
            if name == wide:
                width += 1
            declarations.append(f"reg [{width-1}:0] {name} = {initial};")
    return '''`timescale 1ns/1ps
module bridge_tb;
reg clk = 0, resetn = 0;
always #5 clk = ~clk;
''' + '\n'.join(declarations) + '''
task tick; begin @(posedge clk); #1; end endtask
initial begin
    repeat (5) tick();
    resetn = 1;
    tick();
''' + body + '''
    repeat (3) tick();
    $display("PASS: bridge fixture completed");
    $finish;
end
endmodule
'''


def drive(prefix, word="32'h00010002", last=0, keep="4'hf", ready=1, valid=1):
    return '\n'.join(f"force {prefix}_{field} = {value};" for field, value in
                     (("tdata", word), ("tlast", last), ("tkeep", keep),
                      ("tready", ready), ("tvalid", valid))) + '\ntick();\n'


def idle(prefix):
    return drive(prefix, word="32'bx", last="1'bx", keep="4'bx", ready="1'bx", valid=0)


count = 0

def check(name, source, expected=None, library=STAGE, env_changes=None):
    global count
    directory = STAGE / name
    directory.mkdir(exist_ok=True)
    (directory / "tb.sv").write_text(source)
    run(["iverilog", "-g2012", "-s", "bridge_tb", "-o", "tb.vvp", "tb.sv"],
        directory, directory / "compile.log")
    env = {**os.environ, "ERL_HLS_SIM_DIR": str(directory), "ERL_HLS_SIM_TOP": "bridge_tb"}
    for key in ("ERL_HLS_SIM_APP_ONLY", "ERL_HLS_SIM_PROFILE_ONLY", "ERL_HLS_SIM_SCHEDULER_PROFILE"):
        env.pop(key, None)
    for key, value in (env_changes or {}).items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    with (directory / "simulation.log").open("w") as output:
        result = subprocess.run(["vvp", "-M", str(library), "-m", "xls_sim_bridge", "tb.vvp"],
                                cwd=directory, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=10)
    log = (directory / "simulation.log").read_text()
    if expected:
        assert result.returncode != 0 and expected in log, (name, result.returncode, expected, log)
    else:
        assert result.returncode == 0 and "PASS: bridge fixture completed" in log, (name, log)
    count += 1


build_bridge(STAGE)
# Every fault is tested on both physical directions of both endpoints.
for prefix in ("s_axis", "m_axis", "s_dbg", "m_dbg"):
    endpoint = "app" if "axis" in prefix else "debug"
    direction = "host->DUT" if prefix.startswith("s_") else "DUT->host"
    label = f"{endpoint} {direction}: "
    route = drive(prefix)
    cases = {
        "route_last": (drive(prefix, last=1), "early TLAST"),
        "late_edge_change": (route +
            f"force {prefix}_tdata = 32'h81000100; force {prefix}_tlast = 1; "
            f"#6; force {prefix}_tlast = 0; tick();" + idle(prefix), "missing TLAST"),
        "header_early": (route + drive(prefix, "32'h81000102", last=1), "early TLAST"),
        "header_late": (route + drive(prefix, "32'h81000100"), "missing TLAST"),
        "payload_early": (route + drive(prefix, "32'h81000102") + drive(prefix, last=1), "early TLAST"),
        "payload_late": (route + drive(prefix, "32'h81000101") + drive(prefix), "missing TLAST"),
        "keep": (drive(prefix, keep="4'h7"), "partial TKEEP"),
        "xdata": (drive(prefix, word="32'h0000000x"), "unknown TDATA"),
        "zdata_stalled": (drive(prefix, word="32'hz", ready=0), "unknown TDATA"),
        "xkeep": (drive(prefix, keep="4'bx"), "unknown TKEEP"),
        "xlast": (drive(prefix, last="1'bx"), "unknown TLAST"),
        "xvalid": (drive(prefix, valid="1'bx"), "unknown TVALID"),
        "xready": (drive(prefix, ready="1'bx"), "unknown TREADY"),
        "stall_data": (drive(prefix, ready=0) + drive(prefix, word="32'h2"), "beat changed while stalled"),
        "stall_last": (drive(prefix, ready=0) + drive(prefix, last=1), "beat changed while stalled"),
        "stall_valid": (drive(prefix, ready=0) + idle(prefix), "TVALID dropped while stalled"),
        "reset_abort": (route + idle(prefix) + "resetn = 0; tick();", "reset interrupted transport"),
        "unfinished_frame": (route + idle(prefix), "simulation ended with an incomplete transfer"),
        "unfinished_stall": (drive(prefix, ready=0), "simulation ended with an incomplete transfer"),
    }
    for name, (body, error) in cases.items():
        check(f"{prefix}_{name}", fixture(body), (f"{endpoint}: " if name == "reset_abort" else label) + error)
    # Legal changes after the falling edge must be sampled at the rising edge.
    body = route + f"force {prefix}_tdata = 32'h81000100; force {prefix}_tlast = 0; "
    body += f"#6; force {prefix}_tlast = 1; tick();" + idle(prefix)
    check(f"{prefix}_late_valid", fixture(body))
    # Zero-, one-, and maximum-length frames; legal stable stalls and idle X/Z.
    body = idle(prefix)
    for length in (0, 1, 255, 0):
        body += drive(prefix, ready=0) + drive(prefix, ready=0) + route
        body += drive(prefix, f"32'h810001{length:02x}", last=int(length == 0))
        for index in range(length):
            body += drive(prefix, str(index), last=int(index == length - 1))
    check(f"{prefix}_valid", fixture(body + idle(prefix)))

# Keep an application packet open while independent streams complete packets.
body = drive("s_axis") + idle("s_axis")
for prefix in ("m_dbg", "s_dbg", "m_axis"):
    body += drive(prefix) + drive(prefix, "32'h81000101")
    body += drive(prefix, "32'h42", last=1) + idle(prefix)
body += drive("s_axis", "32'h01000100", last=1) + idle("s_axis")
check("interleaved_streams", fixture(body))

for prefix in ("s_axis", "m_axis", "s_dbg", "m_dbg"):
    check(f"{prefix}_missing", fixture("", missing=prefix + "_tkeep"), "missing signal")
    check(f"{prefix}_width", fixture("", wide=prefix + "_tdata"), "must be 32 bits (got 33)")
check("unknown_reset", fixture("resetn = 1'bx; tick();"), "unknown resetn")
check("idle_reset", fixture("resetn = 0; tick(); resetn = 1; tick();"))
check("no_directory", fixture(""), "ERL_HLS_SIM_DIR is not set", env_changes={"ERL_HLS_SIM_DIR": None})
check("bad_directory", fixture(""), "failed to open transport FIFOs", env_changes={"ERL_HLS_SIM_DIR": str(STAGE / "absent" / "path")})
check("app_only", fixture("", missing="s_dbg_tkeep"), env_changes={"ERL_HLS_SIM_APP_ONLY": "1"})
check("profile_only", fixture("", missing="s_axis_tkeep"), env_changes={"ERL_HLS_SIM_PROFILE_ONLY": "1", "ERL_HLS_SIM_DIR": None})
for operation in ("read", "write"):
    library = STAGE / f"fail_{operation}"
    build_bridge(library, operation)
    # Arm output forwarding via a host transfer, then trigger a FIFO write.
    body = drive("s_axis") + idle("s_axis") + drive("m_axis")
    check(f"fifo_{operation}", fixture(body), f"FIFO {operation} failed", library=library)

print(f"PASS: {count} real-VPI framing, stall, four-state, mode, configuration and I/O checks")
