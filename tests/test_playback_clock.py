# SPDX-License-Identifier: MIT
"""Exercise the player's actual C clock against block-counter aliasing and lifecycle."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "integrations/siliconforest/finch/AVFoundation/player"


class PlaybackClockTests(unittest.TestCase):
    def test_block_counter_phases_drift_and_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="sf-playback-clock-") as directory:
            binary = str(Path(directory) / "clock-test")
            subprocess.run(
                [os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra",
                 "-Werror", "-O2", str(PLAYER / "clock-test.c"), "-lm", "-o", binary],
                check=True, capture_output=True, text=True, timeout=30,
            )
            result = subprocess.run(
                [binary], check=True, capture_output=True, text=True, timeout=30,
            )
            self.assertIn("pause/resume, seeks PASS", result.stdout)
