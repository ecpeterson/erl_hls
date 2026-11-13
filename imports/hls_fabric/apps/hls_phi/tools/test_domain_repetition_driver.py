"""Check owned simulator cleanup without starting a compiler, simulator or host."""

import subprocess
import unittest
from unittest.mock import Mock, call

from test_domain_repetition import retire_simulator


class SimulatorCleanupTests(unittest.TestCase):
    """A simulator ignoring graceful termination must still be killed and reaped."""

    def test_unresponsive_child_is_killed_and_reaped(self) -> None:
        """Timeout of the graceful wait triggers one kill and a final bounded wait."""
        child = Mock()
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired("simulation", 5), -9]
        retire_simulator(child)
        child.terminate.assert_called_once_with()
        child.kill.assert_called_once_with()
        self.assertEqual(child.wait.call_args_list, [call(timeout=5), call(timeout=5)])

    def test_exited_child_is_not_signalled(self) -> None:
        """A child already reaped by poll requires no further termination."""
        child = Mock()
        child.poll.return_value = 0
        retire_simulator(child)
        child.terminate.assert_not_called()
        child.kill.assert_not_called()
        child.wait.assert_not_called()


if __name__ == "__main__":
    unittest.main()
