"""media.sh must only forward well-formed bus names / values to busctl (it is driven by shell state)."""
import os, stat, subprocess, tempfile, unittest

SH = os.path.join(os.path.dirname(__file__), "..", "media.sh")


def run(*args):
    with tempfile.TemporaryDirectory() as d:
        log = os.path.join(d, "calls")
        stub = os.path.join(d, "busctl")
        open(stub, "w").write(f'#!/bin/sh\necho "$@" >> {log}\n')
        os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC)
        subprocess.run([SH, *args], env={**os.environ, "PATH": d + ":" + os.environ["PATH"]}, check=True)
        return open(log).read() if os.path.exists(log) else ""


class MediaSh(unittest.TestCase):
    def test_seek_forwards_valid(self):
        self.assertIn("SetPosition ox /t/1 1000", run("seek", "org.mpris.MediaPlayer2.spotify", "/t/1", "1000"))

    def test_rejects_bad_bus(self):
        self.assertEqual(run("ctl", "evil;rm", "Next"), "")

    def test_rejects_bad_action(self):
        self.assertEqual(run("ctl", "org.mpris.MediaPlayer2.spotify", "Quit"), "")

    def test_rejects_non_numeric_position(self):
        self.assertEqual(run("seek", "org.mpris.MediaPlayer2.spotify", "/t/1", "1;x"), "")

    def test_shuffle_and_loop(self):
        self.assertIn("Shuffle b true", run("shuffle", "org.mpris.MediaPlayer2.spotify", "true"))
        self.assertEqual(run("loop", "org.mpris.MediaPlayer2.spotify", "Bogus"), "")


if __name__ == "__main__":
    unittest.main()
