#!/usr/bin/env python3
"""Check a generated cross-module selector's constant and dynamic optimized XLS IR."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


NODE = re.compile(r"  (?P<return>ret )?(?P<name>[\w.]+): (?P<type>.+?) = (?P<operation>\w+)\((?P<arguments>.*)\)$")
SELECTORS = {"sel", "priority_sel", "one_hot_sel"}


def top_function(text: str) -> tuple[str, list[dict[str, str]]]:
    """Read exactly one top function's nodes, rejecting missing or unfamiliar body syntax."""
    matches = list(re.finditer(r"^top fn ([\w.]+)\([^\n]*\) -> [^\n]+ \{\n(.*?)^\}",
                              text, re.MULTILINE | re.DOTALL))
    if len(matches) != 1:
        raise ValueError("expected exactly one top function")
    match = matches[0]
    nodes = []
    for line in match[2].splitlines():
        if not line.strip():
            continue
        node = NODE.fullmatch(line)
        if node is None:
            raise ValueError(f"unrecognized top-function node: {line}")
        nodes.append(node.groupdict(default=""))
    if sum(bool(node["return"]) for node in nodes) != 1:
        raise ValueError("expected exactly one return node")
    return match[1], nodes


def imported_invocation(text: str) -> str:
    """Require the unoptimized probe to call the compiler-emitted source-helper module."""
    _name, nodes = top_function(text)
    callees = [match[1] for node in nodes if node["operation"] == "invoke"
               if (match := re.search(r"(?:^|, )to_apply=([\w.]+)", node["arguments"]))]
    candidates = [callee for callee in callees if "xls_remote_selector" in callee]
    if not candidates:
        raise ValueError("unoptimized probe did not invoke the source-helper module")
    return candidates[0]


def operations(nodes: list[dict[str, str]]) -> dict[str, int]:
    """Count only nodes in the selected top function, excluding any other package functions."""
    return dict(sorted(Counter(node["operation"] for node in nodes).items()))


def check(raw_constant: str, constant: str, raw_dynamic: str, dynamic: str) -> dict:
    """Require cross-module calls before optimization and constant/dynamic distinction afterward."""
    constant_callee = imported_invocation(raw_constant)
    dynamic_callee = imported_invocation(raw_dynamic)
    constant_name, constant_nodes = top_function(constant)
    dynamic_name, dynamic_nodes = top_function(dynamic)
    constant_ops, dynamic_ops = operations(constant_nodes), operations(dynamic_nodes)
    if any(constant_ops.get(op, 0) for op in SELECTORS | {"invoke"}):
        raise ValueError("constant caller retained selection or a helper invocation")
    result = next(node for node in constant_nodes if node["return"])
    # Identity nodes are semantically neutral; do not require their cleanup pass order.
    by_name = {node["name"]: node for node in constant_nodes}
    seen = set()
    while result["operation"] == "identity":
        name = result["arguments"].split(",", 1)[0]
        if name in seen:
            raise ValueError("cyclic identity nodes")
        seen.add(name)
        if name == "x":
            break
        if name not in by_name:
            raise ValueError("constant caller returned an unexpected identity input")
        result = by_name[name]
    else:
        if result["operation"] != "param" or re.search(r"(?:^|, )name=x(?:,|$)", result["arguments"]) is None:
            raise ValueError("constant caller did not simplify to input x")
    if dynamic_ops.get("invoke", 0):
        raise ValueError("dynamic caller retained a helper invocation")
    if not any(dynamic_ops.get(op, 0) for op in SELECTORS):
        raise ValueError("dynamic caller lost its selector")
    selector_arguments = " ".join(node["arguments"] for node in dynamic_nodes
                                  if node["operation"] in SELECTORS)
    if not all(re.search(r"\b" + name + r"\b", selector_arguments) for name in ("x", "y")):
        raise ValueError("dynamic selection no longer chooses between both data inputs")
    return {"scope": "optimized IR structure; no area or physical timing claim",
            "constant": {"function": constant_name, "source_callee": constant_callee,
                         "operations": constant_ops, "result": "x"},
            "dynamic": {"function": dynamic_name, "source_callee": dynamic_callee,
                        "operations": dynamic_ops}}


def main() -> None:
    """Read the regression's four IR products and retain the checked structural evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    arguments = parser.parse_args()
    names = ("constant.ir", "constant.opt.ir", "dynamic.ir", "dynamic.opt.ir")
    paths = [arguments.stage / name for name in names]
    result = check(*(path.read_text() for path in paths))
    result["inputs"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    (arguments.stage / "source-helper-optimization.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS: cross-module constant selection removed; dynamic selection retained")


if __name__ == "__main__":
    main()
