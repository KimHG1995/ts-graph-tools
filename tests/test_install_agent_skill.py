import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "install-agent-skill.sh"
SOURCE = ROOT / "skills" / "ts-graph"


class InstallAgentSkillTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.destination = self.workspace / "skills directory"

    def run_installer(self, *args, script=SCRIPT):
        return subprocess.run(
            ["bash", str(script), *map(str, args)],
            cwd=self.workspace,
            capture_output=True,
            text=True,
        )

    def assert_installed(self, destination, source=SOURCE):
        link = destination / "ts-graph"
        self.assertTrue(link.is_symlink())
        self.assertTrue(Path(link.readlink()).is_absolute())
        self.assertEqual(link.resolve(), source.resolve())

    def test_installs_for_each_agent_from_another_working_directory(self):
        for agent in ("claude", "codex"):
            with self.subTest(agent=agent):
                destination = self.destination / agent
                result = self.run_installer(agent, destination)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_installed(destination)

    def test_repeating_install_keeps_existing_link(self):
        first = self.run_installer("codex", self.destination)
        self.assertEqual(first.returncode, 0, first.stderr)
        link = self.destination / "ts-graph"
        before = link.lstat()
        target = link.readlink()
        second = self.run_installer("codex", self.destination)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(link.readlink(), target)
        self.assertEqual(link.lstat().st_ino, before.st_ino)
        self.assertEqual(link.lstat().st_mtime_ns, before.st_mtime_ns)

    def test_help_succeeds_without_creating_directories(self):
        result = self.run_installer("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip() or result.stderr.strip())
        self.assertEqual(list(self.workspace.iterdir()), [])

    def test_invalid_arguments_fail_without_creating_directories(self):
        cases = (
            (),
            ("unknown", self.destination),
            ("codex", self.destination, "extra"),
            ("--force", self.destination),
        )
        for args in cases:
            with self.subTest(args=args):
                result = self.run_installer(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(self.workspace.iterdir()), [])

    def test_conflicting_entries_are_preserved(self):
        for kind in ("directory", "file", "symlink", "dangling_symlink"):
            with self.subTest(kind=kind):
                destination = self.destination / kind
                destination.mkdir(parents=True)
                entry = destination / "ts-graph"
                if kind == "directory":
                    entry.mkdir()
                    (entry / "keep.txt").write_text("keep")
                elif kind == "file":
                    entry.write_text("keep")
                else:
                    target = self.workspace / (kind + " target")
                    if kind == "symlink":
                        target.mkdir()
                    entry.symlink_to(target, target_is_directory=True)
                before = entry.lstat()
                target_before = entry.readlink() if entry.is_symlink() else None
                result = self.run_installer("claude", destination)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(entry.lstat().st_ino, before.st_ino)
                self.assertEqual(entry.lstat().st_mtime_ns, before.st_mtime_ns)
                if target_before is not None:
                    self.assertEqual(entry.readlink(), target_before)
                elif kind == "file":
                    self.assertEqual(entry.read_text(), "keep")
                else:
                    self.assertEqual((entry / "keep.txt").read_text(), "keep")

    def test_source_is_found_from_script_in_checkout_with_spaces(self):
        checkout = self.workspace / "source checkout"
        script = checkout / "scripts" / SCRIPT.name
        source = checkout / "skills" / "ts-graph"
        script.parent.mkdir(parents=True)
        source.mkdir(parents=True)
        (source / "SKILL.md").write_text("test skill")
        shutil.copyfile(SCRIPT, script)
        result = self.run_installer("codex", self.destination, script=script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_installed(self.destination, source)


if __name__ == "__main__":
    unittest.main()
