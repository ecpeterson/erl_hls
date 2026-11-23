"""Check independently compiled Phi devices consume their retained policy literally."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import phi_device_build as device_build


class DevicePolicyTests(unittest.TestCase):
    """External command construction must not recreate a scheduler policy."""

    def test_unsupported_policy_rejected_before_outputs(self) -> None:
        """Reject policies this adapter cannot apply before writing wrappers or running tools."""
        for storage, model, error in [("lutram", "unit", "completion storage"),
                                      ("registers", "xc7_7030", "unit delay model")]:
            with self.subTest(storage=storage, model=model), tempfile.TemporaryDirectory() as directory:
                stage = Path(directory)
                policy = {"profile": {"postprocess": {"completion_storage": storage},
                                      "schedules": {"channel": {"delay_model": model}}}}
                args = argparse.Namespace(stage=stage, xls=stage / "xls")
                with patch.object(device_build, "read_build_profile", return_value=policy), \
                        patch.object(device_build, "execute") as execute:
                    with self.assertRaisesRegex(ValueError, error):
                        device_build.build_device(args, {"id": 0})
                execute.assert_not_called()
                self.assertEqual(list(stage.iterdir()), [])

    def test_emitted_flags_and_policy_survive_device_compilation(self) -> None:
        """Pass supplied flags in order and retain the same envelope with output hashes."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            source = stage / "source"
            source.mkdir()
            (source / "phi_device_0.x").write_text("pub proc Top {}\n")
            args = argparse.Namespace(stage=stage, xls=stage / "xls")
            policy = {"version": 1, "profile": {
                          "postprocess": {"completion_storage": "registers"},
                          "schedules": {"channel": {"delay_model": "unit"}}},
                      "codegen_flags": ["--pipeline_stages=7", "--fixture_policy=preserved"]}

            def execute(command: list[str], directory: Path, label: str, *,
                        timeout: int, output: Path) -> None:
                """Retain tiny fake external products so real receipt hashing remains exercised."""
                output.write_text(label + "\n")

            with patch.object(device_build, "read_build_profile", return_value=policy) as read, \
                    patch.object(device_build, "execute", side_effect=execute), \
                    patch.object(device_build, "specialize"), \
                    patch.object(device_build, "instrument_device"):
                device_build.build_device(args, {"id": 0, "application": True})
            read.assert_called_once_with(source / "build-profile.json")
            receipt = json.loads((stage / "device0/build.json").read_text())
            self.assertEqual(receipt["build_profile"], policy)
            self.assertEqual(receipt["commands"][2], [str(args.xls / "codegen_main"),
                *policy["codegen_flags"], "--module_name=phi_device_0",
                str(stage / "device0/phi_device_0.opt.ir")])
            self.assertEqual(set(receipt["outputs"]),
                             {"phi_device_0.ir", "phi_device_0.opt.ir", "phi_device_0.v"})


if __name__ == "__main__":
    unittest.main()
