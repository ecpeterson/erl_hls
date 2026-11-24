"""Record the exact observer binary, verified source archives and applied overlays for capture."""
import hashlib
import json
from pathlib import Path
import sys


def write_identity(stage: Path) -> None:
    """Publish a receipt alongside the built executable; capture rechecks its byte identity."""
    here = Path(__file__).resolve().parent
    inputs = [stage / "nextpnr.tar.gz", stage / "eigen.tar.gz", here / "spacetime.h",
              here / "nextpnr-coverage.patch", here / "nextpnr-spacetime.patch",
              here.parent / "lut_legality/nextpnr-output-pin.patch",
              here.parent / "lut_legality/nextpnr-pin-origins.patch", stage / "bin/nextpnr-spacetime"]
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    meta = {"commit": "68aeeb39f92e39bfb239c7e4a44dd93451fc1889", "sha256": hashes}
    (stage / "bin/spacetime-build.json").write_text(json.dumps(meta, sort_keys=True) + "\n")


if __name__ == "__main__":
    write_identity(Path(sys.argv[1]))
