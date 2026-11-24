#!/usr/bin/env python3
"""Check the Stage 5 routed-feedback parsers without requiring Vivado."""
import tempfile
import unittest
import json
import hashlib
from pathlib import Path

from test_protocol_arithmetic_feedback import (
    ROUTE_FILES,
    ROUTE_SCRIPT,
    recipe,
    routed_evidence,
    timing,
    timing_coverage,
    utilization,
)


def implementation_identities(value: str = "a") -> dict[str, str]:
    """Return the closed identity set carried by a prepared route input."""
    return {
        name: value * 64
        for name in (
            "compiled_json_sha256",
            "implementation",
            "logical_system",
            "plan",
            "product",
            "projection",
            "request",
        )
    }


def route_identity(sources: dict[str, str], value: str = "a") -> dict:
    """Return the complete state-owned identity for one prepared route input."""
    recipe_bytes = ROUTE_SCRIPT.read_bytes()
    return {
        "schema": 1,
        "identities": implementation_identities(value),
        "sources": sources,
        "route_recipe_sha256": hashlib.sha256(recipe_bytes).hexdigest(),
    }


class RoutedFeedbackTests(unittest.TestCase):
    """Reject incomplete physical reports and recipe drift."""

    def test_utilization(self) -> None:
        """Extract complete top-level LUT, FF and DSP counts."""
        report = (
            "| Instance | Module | Total LUTs | Logic LUTs | FFs | DSP Blocks |\n"
            "| arithmetic | (top) | 1404 | 1404 | 903 | 1 |\n"
        )
        self.assertEqual(utilization(report), {"lut": 1404, "ff": 903, "dsp": 1})
        with self.assertRaises(ValueError):
            utilization("| Instance | Module | Total LUTs | FFs |\n")

    def test_timing(self) -> None:
        """Preserve negative setup slack and endpoint failures."""
        header = "WNS(ns) other columns TPWS Total Endpoints\n-------\n"
        result = timing(header + " -0.25 -1.0 3 99 0.04 0 0 99 1.0 0 0 12\n")
        self.assertEqual(result["worst_slack_ns"], -0.25)
        self.assertEqual(result["setup_failing_endpoints"], 3)
        with self.assertRaises(ValueError):
            timing(header + "1 2 3\n")

    def test_timing_coverage(self) -> None:
        """Require clocked internal endpoints without silently accepting missing rows."""
        report = (
            "1. checking no_clock (0)\n"
            "4. checking unconstrained_internal_endpoints (0)\n"
        )
        self.assertEqual(
            timing_coverage(report),
            {"no_clock": 0, "unconstrained_internal_endpoints": 0},
        )
        with self.assertRaises(ValueError):
            timing_coverage("1. checking no_clock (0)\n")

    def test_recipe(self) -> None:
        """Require fixed directives, one thread, a complete route and Vivado 2024.2."""
        values = {
            "tool": "2024.2",
            "part": "xc7z030sbg485-1",
            "top": "protocol_network",
            "clock": "clk",
            "period_ns": "10.0",
            "threads": "1",
            "synth_flatten": "rebuilt",
            "place_directive": "Default",
            "phys_opt_directive": "Default",
            "route_directive": "Default",
            "external_io_false_paths": "true",
            "route_status": "Route Complete",
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "recipe.txt"
            path.write_text("".join(f"{key}={value}\n" for key, value in values.items()))
            self.assertEqual(recipe(path), values)
            path.write_text(path.read_text().replace("threads=1", "threads=2"))
            with self.assertRaises(ValueError):
                recipe(path)
            path.write_text("tool=2024.2\ntool=2024.2\n")
            with self.assertRaises(ValueError):
                recipe(path)
            path.write_text("".join(f"{key}={value}\n" for key, value in values.items()) + "extra=1\n")
            with self.assertRaises(ValueError):
                recipe(path)

    def test_routed_identity(self) -> None:
        """Bind the exact prepared identity and every retained native output."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, route = root / "candidate", root / "route"
            (candidate / "route-input").mkdir(parents=True)
            route.mkdir()
            sources = {"core.v": "", "protocol_network.sv": ""}
            for name in sources:
                (candidate / "route-input" / name).write_text(name)
                (route / name).write_text(name)
                sources[name] = hashlib.sha256(name.encode()).hexdigest()
            route_recipe = ROUTE_SCRIPT.read_bytes()
            (candidate / "route-input/protocol_arithmetic_route.tcl").write_bytes(route_recipe)
            (route / "protocol_arithmetic_route.tcl").write_bytes(route_recipe)
            identity = route_identity(sources)
            encoded = json.dumps(identity)
            (candidate / "route-input/identity.json").write_text(encoded)
            (route / "input-identity.json").write_text(encoded)
            for name in ROUTE_FILES:
                path = route / name
                if not path.exists():
                    path.write_text(name)
            (route / "recipe.txt").write_text(
                "tool=2024.2\npart=xc7z030sbg485-1\ntop=protocol_network\nclock=clk\n"
                "period_ns=10.0\nthreads=1\nsynth_flatten=rebuilt\nplace_directive=Default\n"
                "phys_opt_directive=Default\nroute_directive=Default\n"
                "external_io_false_paths=true\nroute_status=Route Complete\n"
            )
            (route / "utilization.rpt").write_text(
                "| Instance | Module | Total LUTs | Logic LUTs | FFs | DSP Blocks |\n"
                "| arithmetic | (top) | 1404 | 1404 | 903 | 1 |\n"
            )
            (route / "timing.rpt").write_text(
                "WNS(ns) other columns TPWS Total Endpoints\n-------\n"
                " 0.25 0 0 99 0.04 0 0 99 1.0 0 0 12\n"
            )
            (route / "coverage.rpt").write_text(
                "1. checking no_clock (0)\n"
                "4. checking unconstrained_internal_endpoints (0)\n"
            )
            metrics, evidence = routed_evidence("shared3", candidate, route, identity)
            self.assertEqual(metrics["resources"]["dsp"], 1)
            self.assertEqual(
                evidence,
                hashlib.sha256((candidate / "route-evidence.json").read_bytes()).hexdigest(),
            )
            (route / "input-identity.json").write_text("{}")
            with self.assertRaises(ValueError):
                routed_evidence("shared3", candidate, route, identity)

    def test_routed_source_and_recipe_tamper(self) -> None:
        """A copied identity cannot hide changed RTL or a different executing recipe."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, route = root / "candidate", root / "route"
            (candidate / "route-input").mkdir(parents=True)
            route.mkdir()
            sources = {}
            for name in ("core.v", "protocol_network.sv"):
                value = name.encode()
                (candidate / "route-input" / name).write_bytes(value)
                (route / name).write_bytes(value)
                sources[name] = hashlib.sha256(value).hexdigest()
            recipe_bytes = ROUTE_SCRIPT.read_bytes()
            (candidate / "route-input/protocol_arithmetic_route.tcl").write_bytes(recipe_bytes)
            (route / "protocol_arithmetic_route.tcl").write_bytes(recipe_bytes)
            identity = route_identity(sources)
            encoded = json.dumps(identity)
            (candidate / "route-input/identity.json").write_text(encoded)
            (route / "input-identity.json").write_text(encoded)
            (route / "core.v").write_text("changed")
            with self.assertRaisesRegex(ValueError, "routed RTL"):
                routed_evidence("local3", candidate, route, identity)
            (route / "core.v").write_bytes(b"core.v")
            (route / "protocol_arithmetic_route.tcl").write_text("changed")
            with self.assertRaisesRegex(ValueError, "routed recipe"):
                routed_evidence("local3", candidate, route, identity)

    def test_stale_identity_and_self_consistent_recipe_are_rejected(self) -> None:
        """The workflow state and current closed recipe remain independent authorities."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, route = root / "candidate", root / "route"
            (candidate / "route-input").mkdir(parents=True)
            route.mkdir()
            sources = {}
            for name in ("core.v", "protocol_network.sv"):
                value = name.encode()
                (candidate / "route-input" / name).write_bytes(value)
                (route / name).write_bytes(value)
                sources[name] = hashlib.sha256(value).hexdigest()
            recipe_bytes = ROUTE_SCRIPT.read_bytes()
            for base in (candidate / "route-input", route):
                (base / ROUTE_SCRIPT.name).write_bytes(recipe_bytes)
            expected = route_identity(sources)
            stale = route_identity(sources, "b")
            encoded = json.dumps(stale)
            (candidate / "route-input/identity.json").write_text(encoded)
            (route / "input-identity.json").write_text(encoded)
            with self.assertRaisesRegex(ValueError, "workflow state"):
                routed_evidence("local3", candidate, route, expected)
            changed_recipe = b"self-consistent but not the maintained recipe"
            stale["identities"] = implementation_identities()
            stale["route_recipe_sha256"] = hashlib.sha256(changed_recipe).hexdigest()
            encoded = json.dumps(stale)
            (candidate / "route-input/identity.json").write_text(encoded)
            (route / "input-identity.json").write_text(encoded)
            for base in (candidate / "route-input", route):
                (base / ROUTE_SCRIPT.name).write_bytes(changed_recipe)
            with self.assertRaisesRegex(ValueError, "recipe identity"):
                routed_evidence("local3", candidate, route, stale)

    def test_recomputed_source_hash_is_rejected(self) -> None:
        """Rewritten RTL and matching hashes cannot retain the workflow implementation."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, route = root / "candidate", root / "route"
            (candidate / "route-input").mkdir(parents=True)
            route.mkdir()
            sources = {}
            for name in ("core.v", "protocol_network.sv"):
                value = name.encode()
                (candidate / "route-input" / name).write_bytes(value)
                (route / name).write_bytes(value)
                sources[name] = hashlib.sha256(value).hexdigest()
            recipe_bytes = ROUTE_SCRIPT.read_bytes()
            for base in (candidate / "route-input", route):
                (base / ROUTE_SCRIPT.name).write_bytes(recipe_bytes)
            expected = route_identity(sources)
            rewritten_bytes = b"unrelated but self-consistent RTL"
            for base in (candidate / "route-input", route):
                (base / "core.v").write_bytes(rewritten_bytes)
            rewritten_sources = dict(sources)
            rewritten_sources["core.v"] = hashlib.sha256(rewritten_bytes).hexdigest()
            rewritten = route_identity(rewritten_sources)
            encoded = json.dumps(rewritten)
            (candidate / "route-input/identity.json").write_text(encoded)
            (route / "input-identity.json").write_text(encoded)
            with self.assertRaisesRegex(ValueError, "workflow state"):
                routed_evidence("local3", candidate, route, expected)


if __name__ == "__main__":
    unittest.main()
