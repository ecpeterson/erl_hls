"""Compose passive observation services behind one routed debug transport."""
import re
from pathlib import Path


def rtl_files(monitor=False):
    root = Path(__file__).resolve().parents[1] / "priv/rtl/debug"
    names = ["hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v"]
    if monitor:
        names += ["hls_debug_monitor.v", "hls_debug_tap.v", "hls_trace_store.v"]
    return [root / name for name in names]


def boundary(ports, rx, tx, routed):
    if rx is None and tx is None and not routed:
        return None
    if not rx or not tx or rx == tx:
        raise ValueError("monitor requires distinct --monitor-rx and --monitor-tx streams")
    for prefix, direction in ((rx, "input"), (tx, "output")):
        if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_$]*", prefix):
            raise ValueError(f"invalid stream prefix: {prefix}")
        for suffix, width in (("tdata", 32), ("tvalid", 1), ("tready", 1), ("tlast", 1)):
            name = f"{prefix}_{suffix}"
            port = ports.get(name, {})
            expected = ("output" if direction == "input" else "input") if suffix == "tready" else direction
            if port.get("direction") != expected or len(port.get("bits", [])) != width:
                raise ValueError(f"expected {width}-bit {expected} {name}")
    return {"endpoint": 1, "rx": rx, "tx": tx, "routed": bool(routed)}


def wrapper(resources, channels, actors, fingerprint, clock, reset, active_low, monitor):
    clock = f"\\{clock} "
    reset = f"{'!' if active_low else ''}\\{reset} "
    ports = 2 if monitor else 1
    hash_literal = int.from_bytes(bytes.fromhex(fingerprint), "little")
    text = f"""wire [31:0] request_data;
wire [3:0] request_keep;
wire request_last;
wire [{ports-1}:0] request_valid, request_ready, response_last, response_valid, response_ready;
wire [{32*ports-1}:0] response_data;
wire [{4*ports-1}:0] response_keep;
hls_debug_route #(.PORTS({ports}), .ENDPOINTS({"32'h00010002" if monitor else "16'd2"})) route (
    .clk({clock}), .reset({reset}),
    .s_data(s_dbg_tdata), .s_keep(s_dbg_tkeep), .s_last(s_dbg_tlast),
    .s_valid(s_dbg_tvalid), .s_ready(s_dbg_tready),
    .m_data(m_dbg_tdata), .m_keep(m_dbg_tkeep), .m_last(m_dbg_tlast),
    .m_valid(m_dbg_tvalid), .m_ready(m_dbg_tready),
    .request_data(request_data), .request_keep(request_keep), .request_last(request_last),
    .request_valid(request_valid), .request_ready(request_ready),
    .response_data(response_data), .response_keep(response_keep), .response_last(response_last),
    .response_valid(response_valid), .response_ready(response_ready));
hls_topology_debug #(.RESOURCES({resources}), .CHANNELS({channels}), .ACTORS({actors}),
    .FINGERPRINT(256'h{hash_literal:064x})) debug (
    .clk({clock}), .reset({reset}),
    .probe_address(probe_address), .probe_value(probe_value),
    .s_data(request_data), .s_keep(request_keep), .s_last(request_last),
    .s_valid(request_valid[0]), .s_ready(request_ready[0]),
    .m_data(response_data[0 +: 32]), .m_keep(response_keep[0 +: 4]), .m_last(response_last[0]),
    .m_valid(response_valid[0]), .m_ready(response_ready[0]));
"""
    if monitor:
        text += f"hls_debug_monitor #(.ROUTED({int(monitor['routed'])})) boundary_monitor (\n"
        text += f"    .aclk({clock}), .aresetn(!({reset})),\n"
        for side in ("rx", "tx"):
            for suffix in ("tdata", "tvalid", "tready", "tlast"):
                text += f"    .app_{side}_{suffix}(\\{monitor[side]}_{suffix} ),\n"
        text += """    .s_dbg_tdata(request_data), .s_dbg_tkeep(request_keep), .s_dbg_tlast(request_last),
    .s_dbg_tvalid(request_valid[1]), .s_dbg_tready(request_ready[1]),
    .m_dbg_tdata(response_data[32 +: 32]), .m_dbg_tkeep(response_keep[4 +: 4]),
    .m_dbg_tlast(response_last[1]), .m_dbg_tvalid(response_valid[1]), .m_dbg_tready(response_ready[1]));
"""
    return text
