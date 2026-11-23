"""Run bounded board-packaging commands while retaining complete diagnostics."""
from pathlib import Path
import subprocess


def execute(arguments: list[str | Path], cwd: Path, log: Path,
            environment: dict[str, str] | None = None, *, timeout: int = 180) -> None:
    """Append combined output, preserve the child environment, and reject unsuccessful commands."""
    with log.open("a") as output:
        result = subprocess.run([str(value) for value in arguments], cwd=cwd,
                                stdout=output, stderr=subprocess.STDOUT,
                                env=environment, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{arguments[0]} failed ({result.returncode}); see {log}")
