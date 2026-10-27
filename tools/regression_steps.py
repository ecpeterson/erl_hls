"""Small mechanical regression steps; fixtures and expected values remain Erlang-owned."""
from dataclasses import dataclass, field
from pathlib import Path
from collections.abc import Callable
import os
import sys


@dataclass(frozen=True)
class FileText:
    """A generated scalar inserted into one argv element only when the step runs."""
    path: Path
    prefix: str = ""
    suffix: str = ""


@dataclass(frozen=True)
class Command:
    """Direct argv with retained stdout, required products and an explicit outcome."""
    name: str
    argv: list[str | FileText]
    stdout: Path | None = None
    products: tuple[Path, ...] = ()
    directories: tuple[Path, ...] = ()
    timeout: float = 300
    nonempty: bool = False
    rejection: str | None = None


@dataclass(frozen=True)
class Copy:
    """Copy a known support tree's matching files into the fixture directory."""
    source: Path
    pattern: str
    target: Path


@dataclass(frozen=True)
class Rows:
    """Expand an Erlang-generated whitespace table after its fixture writer completes."""
    source: Path
    columns: int
    expand: Callable[[list[str]], list[Command]]


Step = Command | Copy | Rows


@dataclass
class Case:
    """Case-local paths and primitive recipes; constructing a case performs no I/O."""
    root: Path
    xls: Path
    stage: Path
    placements: tuple[str, ...] = ("direct", "ingress_direct")
    steps: list[Step] = field(default_factory=list)
    imports: tuple[str, ...] = ("lib",)
    stage_import: bool = False

    def path(self, name: str) -> Path:
        """Name a case product without changing the legacy artifact layout."""
        return self.stage / name

    def command(self, name: str, argv: list, **kwargs: object) -> None:
        """Append one direct command; strings and paths are separate argv elements."""
        self.steps.append(Command(name, [a if isinstance(a, FileText) else str(a) for a in argv], **kwargs))

    def compile(self) -> None:
        """Prepare the existing test BEAMs, retaining build output and failures."""
        self.command("beam-compile", ["rebar3", "as", "test", "compile"])

    def erl(self, expression: str, *arguments: str | Path, name: str = "fixtures") -> None:
        """Execute the original Erlang fixture/oracle writer with explicit arguments."""
        self.command(name, ["erl", "-noshell", "-pa", self.root / "_build/test/lib/erl_hls/ebin",
            self.root / "_build/test/lib/erl_hls/test", "-eval", expression, "-extra", *(arguments or (self.stage,))], directories=(self.stage,))

    def fixture(self, name: str, placement: str | None = None) -> None:
        """Invoke named Erlang orchestration; schema generation never moves into Python."""
        arguments = f"{name}, hd(init:get_plain_arguments())" + ("" if placement is None else ", " + placement)
        self.erl(f"ok = xls_regression_fixtures:write({arguments}), halt().")

    def generate(self, module: str) -> None:
        """Run one existing write/1 fixture generator after compiling its BEAM."""
        self.compile()
        self.erl(f"ok = {module}:write(hd(init:get_plain_arguments())), halt().")

    def options(self, warnings: bool = False) -> list[str]:
        """Preserve ordered import roots and explicit XLS standard-library selection."""
        paths = ([self.stage] if self.stage_import else []) + [self.root / "priv/xls" / p for p in self.imports]
        return [f"--warnings_as_errors={str(warnings).lower()}", "--dslx_path=" + ":".join(map(str, paths)),
            "--dslx_stdlib_path=" + str(self.xls / "xls/dslx/stdlib")]

    def interpret(self, source: str | Path, *, compare: str = "jit", flags: tuple[str, ...] = (),
                  rejection: str | None = None, warnings: bool = False, override: bool = False) -> None:
        """Run DSLX tests or an explicitly expected typecheck rejection."""
        source = self.path(source) if isinstance(source, str) else source
        tool = os.environ.get("ERL_HLS_INTERPRETER", str(self.xls / "interpreter_main")) if override else self.xls / "interpreter_main"
        self.command(source.stem + "-interpret", [tool, f"--compare={compare}", *self.options(warnings), *flags, source],
            rejection=rejection)

    def convert(self, name: str, top: str, source: str | Path | None = None,
                rejection: str | None = None, optimize: bool = True) -> None:
        """Convert a named entry point and optionally optimize; rejection never proceeds to opt."""
        source = self.path(source or name + ".x") if not isinstance(source, Path) else source
        self.command(name + "-convert", [self.xls / "ir_converter_main", "--top=" + top, *self.options(), source],
            stdout=self.path(name + ".ir"), nonempty=rejection is None, rejection=rejection)
        if optimize and rejection is None:
            self.command(name + "-opt", [self.xls / "opt_main", self.path(name + ".ir")],
                stdout=self.path(name + ".opt.ir"), nonempty=True)

    def codegen(self, name: str, *, source: str | None = None, module: str | None = None,
                flags: tuple[str, ...] = ("--generator=combinational",)) -> None:
        """Generate RTL with exactly the case's schedule and optional module override."""
        options = [*flags, "--use_system_verilog=false"] + ([] if module is None else ["--module_name=" + module])
        self.command(name + "-codegen", [self.xls / "codegen_main", *options, self.path((source or name) + ".opt.ir")],
            stdout=self.path(name + ".v"), nonempty=True)

    def structure(self, name: str, top: str, sources: list[Path]) -> None:
        """Run the existing Yosys structure/loop assertion for these exact RTL files."""
        self.command(name + "-structure", ["bash", self.root / "tools/check_rtl_structure.sh", top,
            self.path(name + "-check"), *sources])

    def simulate(self, name: str, top: str, sources: list[Path], *, flags: list | None = None,
                 arguments: list | None = None, timeout: float = 300) -> None:
        """Compile and run the original Verilog testbench, retaining simulation stdout."""
        self.command(name + "-iverilog", ["iverilog", "-g2012", *(flags or []), "-s", top,
            "-o", self.path(name + ".vvp"), *sources], products=(self.path(name + ".vvp"),))
        self.command(name + "-simulate", ["vvp", self.path(name + ".vvp"), *(arguments or [])],
            stdout=self.path(name + ".sim.log"), timeout=timeout)

    def python(self, name: str, script: str, *arguments: str | Path, timeout: float = 600) -> None:
        """Invoke an existing specialized semantic/formal harness without duplicating it."""
        self.command(name, [sys.executable, self.root / "tools" / script, *arguments], timeout=timeout)

    def library(self, *directories: str) -> None:
        """Stage each complete selected support import root, in the original order."""
        for directory in directories:
            self.steps.append(Copy(self.root / "priv/xls" / directory, "*.x", self.stage))

    def compiled(self, name: str, source: str, artifact: str, stages: int, interval: int | None = None,
                 flags: tuple[str, ...] = ()) -> Path:
        """Reuse the existing production compilation adapter where the old case used it."""
        arguments = [self.path(source), self.xls, "--output", self.path(name), "--top", "Top",
            "--name", artifact, "--pipeline-stages", str(stages), *flags]
        if interval is not None:
            arguments += ["--initiation-interval", str(interval)]
        product = self.path(name + "/" + artifact + ".v")
        self.command(name + "-compile", [sys.executable, self.root / "tools/compile_xls.py", *arguments],
            products=(product,), timeout=900)
        return product

    def yosys(self, name: str, program: str, *, environment: str = "ERL_HLS_YOSYS") -> None:
        """Require successful Yosys assertions, including SAT -verify when requested by a case."""
        self.command(name, [os.environ.get(environment, "yosys"), "-Q", "-T", "-p", program],
            stdout=self.path(name + ".log"), timeout=180)


def pipeline(stages: int, interval: int | None = None, *, flop: bool = True) -> tuple[str, ...]:
    """Common proc flags with explicit case-owned schedule and boundary registers."""
    return (f"--pipeline_stages={stages}", "--delay_model=unit", "--reset=reset", "--fifo_module=") + (
        ("--flop_inputs=false", "--flop_outputs=true") if flop else ()) + (
        (f"--worst_case_throughput={interval}",) if interval is not None else ())
