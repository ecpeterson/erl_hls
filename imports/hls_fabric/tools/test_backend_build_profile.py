"""Check retained policy structure and the thin Erlang emission bridge without XLS."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import backend_build_profile


def fixture() -> dict:
    """Represent a valid Erlang-emitted record; arbitrary flag bytes test pass-through ownership."""
    return {"version": 1, "profile": {"backend": "channel_scheduler", "placement": "prepared_source",
        "frame_abi": {"name": "canonical_actor_v1", "header_bits": 32, "payload_bits": 96,
            "frame_bits": 128, "payload_words": 3, "parameterized": False},
        "schedules": {"channel": {"pipeline_stages": 2, "initiation_interval": "tool_default",
            "delay_model": "test-model", "executor_result_delay": 0, "flop_inputs": False,
            "flop_outputs": True, "fifo_module": "none"}},
        "tools": {"provider": "xls", "identity": "external_compilation"},
        "postprocess": {"completion_storage": "registers"}},
        "codegen_flags": ["--owner_rendered_option=unchanged"]}


class BackendBuildProfileTests(unittest.TestCase):
    """The reader checks shape while the owning Erlang module retains all scheduling decisions."""

    def test_reader_preserves_flags_without_checkout_imports(self) -> None:
        """A copied helper reads emitted policy without backend_paths, compiler tools or BEAMs."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained = root / "backend_build_profile.py"
            shutil.copyfile(backend_build_profile.__file__, retained)
            policy = root / "policy.json"
            policy.write_text(json.dumps(fixture()))
            expression = "import runpy,sys;print(runpy.run_path(sys.argv[1])['read'](sys.argv[2])['codegen_flags'][0])"
            result = subprocess.run([sys.executable, "-I", "-c", expression, str(retained), str(policy)],
                                    check=True, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.stdout.strip(), "--owner_rendered_option=unchanged")
            self.assertEqual(backend_build_profile.read(policy), fixture())

    def test_reader_rejects_wrong_backend_and_malformed_records(self) -> None:
        """Reject owners, unsupported versions and malformed data before an adapter accesses it."""
        examples = []
        for path, replacement in ((["version"], True), (["profile", "backend"], "source_protocol"),
                (["profile", "schedules", "channel", "initiation_interval"], False),
                (["profile", "postprocess", "completion_storage"], "block_ram"),
                (["codegen_flags"], ["--value=bad\nargument"])):
            value = copy.deepcopy(fixture())
            current = value
            for part in path[:-1]:
                current = current[part]
            current[path[-1]] = replacement
            examples.append(value)
        with tempfile.TemporaryDirectory() as temporary:
            policy = Path(temporary) / "policy.json"
            for value in examples:
                with self.subTest(value=value):
                    policy.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        backend_build_profile.read(policy)

    def test_emit_selects_beams_and_forwards_policy_options(self) -> None:
        """Only the Erlang command interprets options; the adapter keeps paths and profile explicit."""
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "policy with spaces.json"
            public = Path("/explicit compiler")

            def run(command: list[str], **options: object) -> subprocess.CompletedProcess:
                """Stand in for the CLI while retaining its exact command and selected environment."""
                self.assertEqual(options["env"], {"ERL_AFLAGS": "selected"})
                self.assertEqual(command[command.index("--output") + 1], str(output))
                self.assertEqual(command[command.index("--initiation-interval") + 1], "tool_default")
                self.assertEqual(command[command.index("--delay-model") + 1], "test-model")
                output.write_text(json.dumps(fixture()))
                return subprocess.CompletedProcess(command, 0, "", "")

            with patch("backend_paths.erlang_environment", return_value={"ERL_AFLAGS": "selected"}) as environment, \
                    patch("backend_build_profile.subprocess.run", side_effect=run):
                self.assertEqual(backend_build_profile.emit(output, profile="test", public=public,
                    initiation_interval=None, delay_model="test-model"), fixture())
            environment.assert_called_once_with("test", compiler=public)

    def test_emit_preserves_cli_diagnostic(self) -> None:
        """A rejected policy never gets replaced by Python defaults or a missing-file exception."""
        with patch("backend_paths.erlang_environment", return_value={}), \
                patch("backend_build_profile.subprocess.run", return_value=subprocess.CompletedProcess(
                    [], 1, "", "invalid_schedule_option: rejected")):
            with self.assertRaisesRegex(RuntimeError, "invalid_schedule_option: rejected"):
                backend_build_profile.emit(Path("unused.json"), stages=False)


if __name__ == "__main__":
    unittest.main()
