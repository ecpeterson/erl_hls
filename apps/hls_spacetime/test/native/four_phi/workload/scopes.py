"""Link measured primitives to retained hierarchy and unambiguous named output connections."""

from pathlib import Path
import json


def scope(path: str, ids: dict[str, int]) -> int | None:
    """Look up the nearest recorded, enclosing RTL instance of a hierarchical name."""
    while "." in path:
        path = path.rsplit(".", 1)[0]
        if path in ids:
            return ids[path]
    return None


def links(backend: str, run: Path, units: list, cells: list) -> dict[str, int]:
    """Classify a cell by literal hierarchy or one named output scope. Omit ambiguous or absent links."""
    ids = {u["path"]: i for i, u in enumerate(units) if u["path"]}
    if backend == "vivado":
        return {
            name: s
            for name, _ in cells
            if (s := scope(name.replace("/", "."), ids)) is not None
        }
    module = json.loads((run / "native/synth.json").read_bytes())["modules"][
        "phi_timing_harness"
    ]
    nets = {}
    for name, entry in module["netnames"].items():
        # Generated $abc/$flatten net names can embed source text anywhere.
        # Only accept actual hierarchical net names in the retained decoder.
        if not name.startswith("decoder."):
            continue
        s = scope(name, ids)
        if s is not None:
            for bit in entry["bits"]:
                if isinstance(bit, int):
                    nets.setdefault(bit, set()).add(s)
    result = {}
    for name, cell in module["cells"].items():
        path = name.removeprefix("$flatten").replace("\\", "")
        s = (
            scope(path.split(".$", 1)[0] + ".", ids)
            if path.startswith("decoder.")
            else None
        )
        if s is None:
            found = set()
            for port, bits in cell["connections"].items():
                if cell["port_directions"][port] == "output":
                    for bit in bits:
                        found.update(nets.get(bit, ()))
            if len(found) == 1:
                s = found.pop()
        if s is not None:
            result[name] = s
    return result
