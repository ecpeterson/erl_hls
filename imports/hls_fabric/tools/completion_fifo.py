"""Select distributed payload RAM for generated scheduler completion FIFOs.

This guarded RTL legalization preserves XLS control, capacities and handshakes.
Unrecognized compiler output fails closed rather than receiving a guessed edit.
"""

import hashlib
import re

MODULE = re.compile(r"^module\s+(\w+)\s*\(.*?^endmodule\b[^\n]*", re.M | re.S)


def ports(module: str) -> dict[str, str]:
    """Require simple named XLS wire ports and retain direction and bit width."""
    header = module.split(");", 1)[0].split("(", 1)[1]
    result = {}
    for declaration in header.split(","):
        match = re.fullmatch(r"\s*(input|output)\s+wire\s*(\[[0-9]+:[0-9]+\])?\s*(\w+)\s*", declaration)
        if match is None or match[3] in result:
            raise ValueError("unsupported or duplicate FIFO port declaration")
        result[match[3]] = match[1] + (match[2] or "[0:0]")
    return result


def payload_memory(module: str) -> tuple[str, dict]:
    """Preserve a checked XLS ring's control while expressing one unreset write port."""
    declaration = re.search(r"  reg \[(\d+):0\] buf__1\[0:(\d+)\];", module)
    if declaration is None:
        raise ValueError("expected general ring payload array")
    width, rows = int(declaration[1]) + 1, int(declaration[2]) + 1
    if rows < 3 or ports(module).get("push_data") != f"input[{width-1}:0]":
        raise ValueError("unsupported ring dimensions")
    if "assign pushed = ~is_full_bool & push_valid;" not in module:
        raise ValueError("unexpected accepted-write predicate")
    row_update = re.search(
        r"assign (array_update_\d+)\[__i0\] = head == __i0 \? push_data : buf__1\[__i0\];", module
    )
    if row_update is None:
        raise ValueError("unexpected row update")
    update_name = row_update[1]
    original = module
    module = module.replace(declaration[0], '  (* ram_style = "distributed" *)' + declaration[0].lstrip())
    write_enable = None
    for row in range(rows):
        reset = f"      buf__1[{row}] <= buf__1_init[{row}];\n"
        if module.count(reset) != 1:
            raise ValueError("unexpected payload reset")
        module = module.replace(reset, "")
        update = rf"      buf__1\[{row}\] <= (pushed|did_push_occur) \? {update_name}\[{row}\] : buf__1\[{row}\];\n"
        matches = list(re.finditer(update, module))
        if len(matches) != 1 or write_enable not in (None, matches[0][1]):
            raise ValueError("unexpected or inconsistent payload write predicate")
        write_enable = matches[0][1]
        module, count = re.subn(update, "", module)
        if count != 1:
            raise ValueError("unexpected payload write")
    # Vivado classifies memory ports during elaboration, before removing dead logic.
    # The abandoned row-update network reads every row and prevents RAM inference.
    declaration = rf"  wire \[{width-1}:0\] {update_name}\[0:{rows-1}\];\n"
    fanout = (
        rf"  for \(genvar __i0 = 0; __i0 < {rows}; __i0 = __i0 \+ 1\) begin : \w+\n"
        rf"    assign {update_name}\[__i0\] = head == __i0 \? push_data : buf__1\[__i0\];\n"
        r"  end\n"
    )
    if (
        len(re.findall(rf"\b{update_name}\b", module)) != 2
        or len(re.findall(declaration, module)) != 1
        or len(re.findall(fanout, module)) != 1
    ):
        raise ValueError("payload row-update network is not exclusively dead")
    module = re.sub(declaration, "", module)
    module = re.sub(fanout, "", module)
    module = module.replace(
        "endmodule",
        """  // Payload is unspecified while empty; reset only invalidates ring metadata.
  // One addressed write preserves all independent scheduler result channels.
  always @(posedge clk) begin
    if (!reset && WRITE_ENABLE) buf__1[head] <= push_data;
  end
endmodule""".replace(
            "WRITE_ENABLE", write_enable
        ),
    )
    if ports(original) != ports(module):
        raise AssertionError("changed FIFO interface")
    return module, {
        "width": width,
        "physical_rows": rows,
        "write_enable": write_enable,
        "removed_dead_payload_fanout": True,
    }


def transform(rtl: str) -> tuple[str, dict]:
    """Modify only deep completion FIFO modules, rejecting shared unrelated uses."""
    instances = re.findall(r"^\s*(fifo_for_depth_\w+)\s+(\w+)\s*\(", rtl, re.M)
    selected = {
        kind
        for kind, name in instances
        if name == "materialized_fifo_fifo__executor_result_"
        and not kind.startswith(("fifo_for_depth_0_", "fifo_for_depth_1_"))
    }
    if not selected:
        raise ValueError("no deep completion FIFOs")
    if any(
        kind in selected and name != "materialized_fifo_fifo__executor_result_" for kind, name in instances
    ):
        raise ValueError("completion FIFO module also used elsewhere")
    audit = {}

    def change(match: re.Match) -> str:
        """Rewrite selected definitions once and retain all other module text."""
        if match[1] not in selected:
            return match[0]
        if match[1] in audit:
            raise ValueError("duplicate FIFO definition")
        body, dimensions = payload_memory(match[0])
        audit[match[1]] = dimensions
        return body

    candidate = MODULE.sub(change, rtl)
    if set(audit) != selected:
        raise ValueError("missing FIFO definition")
    mask = lambda text: MODULE.sub(lambda m: "<completion FIFO>" if m[1] in selected else m[0], text)
    if mask(candidate) != mask(rtl):
        raise AssertionError("non-FIFO RTL changed")
    return candidate, {
        "modules": audit,
        "unchanged_non_fifo_sha256": hashlib.sha256(mask(rtl).encode()).hexdigest(),
    }
