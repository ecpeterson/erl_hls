"""Keep register-service compiler refreshes tied to the owning build profile."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import build_regsvc_rtl as regsvc


def compiler_source(repository: Path) -> Path:
    """Create one canonical umbrella facade and its tool-package marker."""
    package = repository / "tools/erl_hls_tools"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text('"""Fixture compiler package."""\n')
    source = repository / "apps/erl_hls"
    (source / "src").mkdir(parents=True)
    return source


def compiler_projection(repository: Path, profile: str, source: Path) -> Path:
    """Project one canonical facade into the selected fake Rebar profile."""
    application = repository / "_build" / profile / "lib/erl_hls"
    (application / "ebin").mkdir(parents=True)
    (application / "src").symlink_to(source / "src", target_is_directory=True)
    return application


class RegsvcContextTests(unittest.TestCase):
    """Source resolution follows the refresh; explicit contexts are never rebuilt or replaced."""

    def test_refresh_precedes_default_resolution(self) -> None:
        """A clean fabric build creates the requested profile before dependency lookup."""
        for profile in ("default", "test"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                project = Path(directory)
                source = compiler_source(project)
                selected = project / "_build" / profile / "lib/erl_hls"

                def refresh(arguments: list[str], *, cwd: Path, check: bool,
                            env: dict[str, str]) -> None:
                    """Model rebar publishing the profile without invoking an external command."""
                    expected = ["rebar3", "compile"] if profile == "default" else ["rebar3", "as", profile, "compile"]
                    self.assertEqual(arguments, expected)
                    self.assertEqual(cwd, project)
                    self.assertTrue(check)
                    self.assertEqual(env["ERL_AFLAGS"], "")
                    self.assertFalse(selected.exists())
                    (project / "_build" / profile / "lib/hls_fabric/ebin").mkdir(parents=True)
                    compiler_projection(project, profile, source)

                with patch.object(regsvc, "BACKEND", project), patch.object(
                        regsvc.subprocess, "run", side_effect=refresh) as run:
                    self.assertEqual(regsvc.compiler_context(None, profile), source.resolve())
                    run.assert_called_once()

    def test_override_uses_prebuilt_matching_profile(self) -> None:
        """An explicit root uses its own beams without rebuilding that root or the fabric."""
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            selected = compiler_source(project)
            compiler_projection(project, "custom", selected)
            with patch.object(regsvc, "BACKEND", project), patch.object(regsvc.subprocess, "run") as run:
                self.assertEqual(regsvc.compiler_context(selected, "custom"), selected.resolve())
                with self.assertRaisesRegex(FileNotFoundError, "default compiler beams"):
                    regsvc.compiler_context(selected, "default")
                run.assert_not_called()

    def test_source_only_override_cannot_fall_back(self) -> None:
        """A valid fabric dependency does not supply beams for an unbuilt override."""
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "_build/default/lib/hls_fabric/ebin").mkdir(parents=True)
            built = compiler_source(project)
            compiler_projection(project, "default", built)
            selected = compiler_source(project / "source-only")
            with patch.object(regsvc, "BACKEND", project), patch.object(regsvc.subprocess, "run") as run:
                with self.assertRaisesRegex(FileNotFoundError, "compiler beams"):
                    regsvc.compiler_context(selected, "default")
                run.assert_not_called()

    def test_runtime_provenance_uses_sibling_application(self) -> None:
        """Manifest inputs retain runtime sources from the umbrella sibling application."""
        with tempfile.TemporaryDirectory() as directory:
            apps = Path(directory) / "apps"
            public = apps / "erl_hls"
            runtime = apps / "hls_runtime/src/runtime"
            runtime.mkdir(parents=True)
            first = runtime / "first.erl"
            second = runtime / "second.erl"
            first.touch()
            second.touch()
            self.assertEqual(regsvc.runtime_sources(public), [first, second])


if __name__ == "__main__":
    unittest.main()
