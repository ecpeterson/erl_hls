#!/usr/bin/env python3
"""Check paired restart identity fencing without contacting physical boards."""

import subprocess
import unittest
from unittest import mock

import restart_repetition_pair as restart


class RestartTests(unittest.TestCase):
    """Exercise proof of a new kernel and verified endpoint recovery."""

    @mock.patch.object(restart.time, "sleep")
    @mock.patch.object(restart, "ssh_command")
    def test_await_reboot_rejects_old_kernel(self, command: mock.Mock,
                                             _sleep: mock.Mock) -> None:
        """An answering old kernel is not mistaken for a completed reset."""
        command.side_effect = [
            subprocess.CompletedProcess([], 0, "old\nPASS: stale\n", ""),
            subprocess.CompletedProcess([], 0, "new\nPASS: installed\n", ""),
        ]
        target, output = restart.await_reboot(
            restart.Target("a", "192.0.2.1"), "key", "old", float("inf"))
        self.assertEqual(target.role, "a")
        self.assertEqual(output, "PASS: installed\n")

    @mock.patch.object(restart, "ssh_command")
    def test_boot_identity_requires_success(self, command: mock.Mock) -> None:
        """The pre-reset fence comes only from a successful SSH read."""
        command.return_value = subprocess.CompletedProcess([], 0, "boot-id\n", "")
        _, identity = restart.boot_identity(restart.Target("b", "192.0.2.2"), "key")
        self.assertEqual(identity, "boot-id")


if __name__ == "__main__":
    unittest.main()
