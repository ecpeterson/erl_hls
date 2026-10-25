"""Check experimental source derivation without invoking XLS or RTL tools."""
from backend_paths import ROOT
from compile_phi_decoder_profile import INPUTS, checked_inputs
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "pipeline_ablation", ROOT / "experiments/07-openxc7/timing_chains/pipeline_ablation.py")
ablation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ablation)


class AblationInputs(unittest.TestCase):
    """Retain exact checked parents when intentionally changing generated actors."""

    def setUp(self) -> None:
        """Prepare the smallest source contract containing a completion boundary."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.reference, self.stage = root / "reference", root / "stage"
        self.reference.mkdir()
        self.stage.mkdir()
        files = {
            "actor.x": """pub proc SharedService<
let result = state.completed; let retire_valid = buffered_can_retire;
let completed_valid = if accept_executor_result { incoming_valid }
  else { state.completed_valid };
""",
            "phi_decoder_profile_topology.x": "import actor;\n",
            "phi_decoder_profile_top.v": "// wrapper\n",
            "phi_decoder_profile.json": "{}\n",
        }
        for name, content in files.items():
            (self.reference / name).write_text(content)
        self.parent = {"version": 1, "ram_configurations": "state:1R1W:read:write",
                       "ram_configuration": "f" * 64,
                       "inputs": {name: ablation.sha(self.reference / name) for name in files}}
        (self.reference / INPUTS).write_text(json.dumps(self.parent))

    def test_derived_contract_binds_transformation_and_exact_parent(self) -> None:
        """Permit the requested actor rewrite while retaining unchanged input identities."""
        sources = ablation.prepare_sources(self.reference, self.stage, {"completion"})
        derived = checked_inputs(self.stage, assets=self.stage)
        provenance = derived["derivation"]
        self.assertEqual(provenance["parent_manifest"], self.parent)
        self.assertEqual(provenance["parent_manifest_sha256"],
                         ablation.sha(self.reference / INPUTS))
        self.assertEqual(provenance["script_sha256"], ablation.sha(Path(ablation.__file__)))
        self.assertEqual(provenance["removed_boundaries"], ["completion"])
        self.assertEqual(provenance["transformed_inputs"],
                         {"actor.x": {**sources["actor.x"], "removed_boundaries": ["completion"]}})
        self.assertNotEqual(derived["inputs"]["actor.x"], self.parent["inputs"]["actor.x"])
        for name in self.parent["inputs"].keys() - {"actor.x"}:
            self.assertEqual(derived["inputs"][name], self.parent["inputs"][name])
        self.assertEqual(derived["ram_configuration"], self.parent["ram_configuration"])
        self.assertEqual(derived["ram_configurations"], self.parent["ram_configurations"])

    def test_parent_drift_is_rejected_before_copying(self) -> None:
        """Reject stale captured actors instead of blessing their current bytes."""
        (self.reference / "actor.x").write_text("changed before the requested transformation")
        with self.assertRaisesRegex(ValueError, "generated profile input changed: actor.x"):
            ablation.prepare_sources(self.reference, self.stage, {"completion"})
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_unbound_shared_actor_cannot_be_transformed(self) -> None:
        """Require a parent binding for every actor selected by the experiment."""
        (self.reference / "unbound.x").write_bytes((self.reference / "actor.x").read_bytes())
        with self.assertRaisesRegex(ValueError, "not bound by parent inputs: unbound.x"):
            ablation.prepare_sources(self.reference, self.stage, {"completion"})
        self.assertFalse((self.stage / INPUTS).exists())


if __name__ == "__main__":
    unittest.main()
