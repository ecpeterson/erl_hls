#!/usr/bin/env python3
"""Fault-inject regression execution and check case selection/coverage without XLS or HDL tools."""
import argparse
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import patch

from erl_hls_tools import compile_xls as executor
import regression_cases
from regression_inventory import load_inventory
from regression_steps import Case, Command, FileText, Rows
from run_regression import ROOT, main, make_cases, run_case, selected


class ExecutionTests(unittest.TestCase):
    """Expected rejection, SAT-like failure and timeouts share the production process lifecycle."""

    def test_executor_defaults_still_require_successful_output(self) -> None:
        """Regression options do not weaken the existing production executor contract."""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            with self.assertRaisesRegex(ValueError, "empty"):
                executor.run([sys.executable, "-c", "pass"], work, "out", 2)
            with self.assertRaisesRegex(RuntimeError, "exited 1"):
                executor.run([sys.executable, "-c", "print('output'); raise SystemExit(1)"], work, "out", 2)
            metrics = executor.run([sys.executable, "-c", "print('output')"], work, "out", 2)
            self.assertEqual(0, metrics["returncode"])
            self.assertGreater((work / "out").stat().st_size, 0)

    def test_expected_rejection_requires_matching_positive_exit(self) -> None:
        """Success, unrelated failures and signals never satisfy a negative compilation test."""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            metrics = executor.run([sys.executable, "-c", "import sys; print('TypeMismatch', file=sys.stderr); sys.exit(2)"],
                work, "out", 2, allow_empty=True, expect_failure="TypeMismatch")
            self.assertEqual(2, metrics["returncode"])
            for program in ("print('TypeMismatch')", "raise SystemExit(1)",
                    f"import os; print('TypeMismatch', flush=True); os.kill(os.getpid(), {signal.SIGTERM})"):
                with self.subTest(program=program), self.assertRaisesRegex(RuntimeError, "expected rejection"):
                    executor.run([sys.executable, "-c", program], work, "out", 2,
                        allow_empty=True, expect_failure="TypeMismatch")

    def test_timeout_cannot_satisfy_expected_rejection(self) -> None:
        """Even a matching diagnostic followed by a hang retains a failure receipt."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "case"
            case = Case(ROOT, Path("/unused"), stage)
            case.command("negative", [sys.executable, "-c", "import time; print('TypeMismatch', flush=True); time.sleep(30)"],
                timeout=0.3, rejection="TypeMismatch")
            with self.assertRaises(TimeoutError):
                run_case("timeout", case)
            result = json.loads((stage / "regression.json").read_text())
            self.assertEqual("failed", result["status"])
            log = Path(result["steps"][0]["log"])
            self.assertIn("TypeMismatch", (log / "stdout.log").read_text())
            self.assertIn("exceeded", json.loads((log / "time.json").read_text())["error"])

    def test_failed_assertion_stops_later_steps(self) -> None:
        """A failed formal/simulation assertion cannot be treated as an expected compiler rejection."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "case"
            marker = stage / "should-not-run"
            case = Case(ROOT, Path("/unused"), stage)
            case.command("sat-equivalence", [sys.executable, "-c", "import sys; print('SAT failed', file=sys.stderr); sys.exit(1)"])
            case.command("later", [sys.executable, "-c", f"from pathlib import Path; Path({str(marker)!r}).touch()"])
            with self.assertRaises(RuntimeError):
                run_case("assertion", case)
            self.assertFalse(marker.exists())
            result = json.loads((stage / "regression.json").read_text())
            self.assertEqual("failed", result["steps"][0]["status"])
            self.assertIn("SAT failed", (Path(result["steps"][0]["log"]) / "stderr.log").read_text())

    def test_generated_rows_and_scalars_run_after_fixture_writer(self) -> None:
        """Generated argv values preserve spaces and shell metacharacters as literal data."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "case with spaces"
            root = Path(directory) / "checkout"
            root.mkdir()
            case = Case(root, Path("/unused"), stage)
            table, scalar = stage / "variants.txt", stage / "count"
            case.command("generate", [sys.executable, "-c",
                f"from pathlib import Path; Path({str(table)!r}).write_text('one 7\\n'); Path({str(scalar)!r}).write_text('literal $() value')"])
            def expand(row: list[str]) -> list[Command]:
                """Forward the generated case dimensions to a child that prints exact argv and cwd."""
                return [Command("consume", [sys.executable, "-c", "import os,sys; print(os.getcwd()); print(sys.argv[1:])",
                    row[0], row[1], FileText(scalar, "prefix=", "!")], stdout=stage / "observed.log")]
            case.steps.append(Rows(table, 2, expand))
            result = run_case("generated", case)
            self.assertEqual("passed", result["status"])
            output = (stage / "observed.log").read_text()
            self.assertIn(str(root), output)
            self.assertIn("prefix=literal $() value!", output)
            self.assertEqual(2, len(result["steps"]))

    def test_required_product_parent_is_created_by_command(self) -> None:
        """A required product is a postcondition, not permission to precreate a compiler output."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "case"
            product = stage / "managed-output" / "generated.v"
            case = Case(ROOT, Path("/unused"), stage)
            case.command("managed-compile", [sys.executable, "-c",
                f"from pathlib import Path; p = Path({str(product)!r}); "
                "assert not p.parent.exists(); p.parent.mkdir(); p.write_text('generated')"],
                products=(product,))
            result = run_case("managed-output", case)
            self.assertEqual("passed", result["status"])
            self.assertEqual("generated", product.read_text())

    def test_fresh_stage_and_required_products(self) -> None:
        """Reused artifacts fail before execution; a missing new simulator also fails."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "case"
            stage.mkdir()
            (stage / "old.vvp").write_text("stale")
            case = Case(ROOT, Path("/unused"), stage)
            with patch.object(executor, "run", side_effect=AssertionError("stale stage executed")):
                with self.assertRaisesRegex(ValueError, "absent or empty"):
                    run_case("stale", case)
            stage = Path(directory) / "fresh"
            case = Case(ROOT, Path("/unused"), stage)
            case.command("missing-product", [sys.executable, "-c", "pass"], products=(stage / "missing.vvp",))
            with self.assertRaisesRegex(ValueError, "missing regression product"):
                run_case("missing", case)


class DescriptionTests(unittest.TestCase):
    """One inventory drives names/defaults; descriptions keep all selected execution boundaries explicit."""

    def test_inventory_cases_preview_without_tools_or_generated_files(self) -> None:
        """Dry-run must describe every registered case, including deferred variant tables."""
        with patch.object(executor, "run", side_effect=AssertionError("preview executed")), redirect_stdout(io.StringIO()) as output:
            main(["/nonexistent/xls", "--all", "--dry-run"])
        rows = json.loads(output.getvalue())
        inventory = load_inventory()
        self.assertEqual(set(inventory["cases"]), {row["case"] for row in rows})
        self.assertEqual(26, len(rows))
        self.assertEqual(1, sum(step.get("name") == "beam-compile" for row in rows for step in row["steps"]))
        self.assertTrue(any(step["kind"] == "generated_rows" for row in rows for step in row["steps"]))
        for row in rows:
            self.assertEqual(ROOT / inventory["cases"][row["case"]]["default_stage"], Path(row["stage"]).parent)

    def test_empty_json_and_duplicate_selection(self) -> None:
        """An empty CI selection is a no-op; repeated names run once in requested order."""
        with patch.object(executor, "run", side_effect=AssertionError("empty selection executed")), redirect_stdout(io.StringIO()):
            main(["--cases-json", "[]"])
        args = argparse.Namespace(cases_json='["helpers","binary","helpers"]', cases=None, all=False, changed_since=None)
        self.assertEqual(["helpers", "binary"], selected(args, load_inventory(), ROOT))

    def test_explicit_stages_and_placement_selection(self) -> None:
        """Single-case stages stay exact; multi-case roots separate outputs without losing placement arguments."""
        inventory = load_inventory()
        base = Path("/tmp/regression-preview").resolve()
        one = make_cases(["mixed_topology"], inventory, ROOT, Path("/xls"), base, ("ingress_direct",))
        self.assertEqual(base, one[0][1].stage)
        commands = [step for step in one[0][1].steps if isinstance(step, Command)]
        fixtures = [step for step in commands if step.name == "fixtures"]
        self.assertEqual(1, len(fixtures))
        self.assertIn("ingress_direct", " ".join(fixtures[0].argv))
        many = make_cases(["helpers", "binary"], inventory, ROOT, Path("/xls"), base, ("direct",))
        self.assertEqual([base / "helpers", base / "binary"], [case.stage for _, case in many])

    def test_special_capabilities_and_dependent_debug_are_explicit(self) -> None:
        """SAT, negative compilation and generated-debug dependencies survive the migration."""
        helper = Case(ROOT, Path("/xls"), Path("/stage"))
        regression_cases.helpers(helper)
        commands = [step for step in helper.steps if isinstance(step, Command)]
        sat = next(step for step in commands if step.name == "equivalence")
        self.assertIn("sat -verify -prove trigger 0", " ".join(sat.argv))
        self.assertEqual(11, sum(step.rejection is not None for step in commands))
        frames = Case(ROOT, Path("/xls"), Path("/stage"))
        regression_cases.application_frames(frames)
        self.assertEqual("frame-backpressure-debug", frames.steps[-1].name)
        self.assertIn("/stage/DebugTop-p2-ii1.v", frames.steps[-1].argv)


if __name__ == "__main__":
    unittest.main()
