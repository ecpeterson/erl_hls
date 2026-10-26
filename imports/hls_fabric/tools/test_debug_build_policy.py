"""Check debug application builds use emitted policy without changing peripheral recipes."""
import json
from pathlib import Path
from backend_build_profile import emit
from compiler_paths import compiler_root, compiler_tool
from build_phi_debug import compile_dslx

public = compiler_root("test")
BuildFixture = compiler_tool(public, "testing").BuildFixture


class DebugPolicyTests(BuildFixture):
    """Retain one actual Erlang policy through mocked XLS application commands."""

    def test_application_policy_and_peripheral_recipe(self) -> None:
        """Application flags come from the sidecar; peripheral default boundary flops stay unspecified."""
        policy_path = self.inputs / "build-profile.json"
        policy = emit(policy_path, profile="test", public=public, stages=4, initiation_interval=2)
        compile_dslx(self.xls, self.inputs, "counter", "Top", 4,
                     rams="fixture:1RW:1", build_profile=policy_path)
        receipt = json.loads((self.inputs / "counter.build.json").read_text())
        self.assertEqual(receipt["build_profile"], policy)
        self.assertEqual(receipt["commands"][2][1][1:],
                         [*policy["codegen_flags"], "--ram_configurations=fixture:1RW:1", "counter.opt.ir"])
        self.assertIn(policy_path.name, receipt["assets"])
        with self.assertRaisesRegex(ValueError, "requires an emitted"):
            compile_dslx(self.xls, self.inputs, "counter", "Top", 2, rams="fixture:1RW:1")
        compile_dslx(self.xls, self.inputs, "counter", "Top", 3, ii=2)
        peripheral = json.loads((self.inputs / "counter.build.json").read_text())
        self.assertIsNone(peripheral["build_profile"])
        flags = peripheral["commands"][2][1]
        self.assertIn("--pipeline_stages=3", flags)
        self.assertFalse(any(flag.startswith("--flop_") for flag in flags))
