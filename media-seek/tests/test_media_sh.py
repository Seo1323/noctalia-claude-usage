"""media.sh must only forward well-formed bus names / values to busctl (it is driven by shell state)."""
import os, stat, subprocess, tempfile, unittest

SH = os.path.join(os.path.dirname(__file__), "..", "media.sh")


def run(*args, stub_body=None, capture=False):
    """Runs media.sh with a fake busctl on PATH; returns the busctl call log (or stdout if capture)."""
    with tempfile.TemporaryDirectory() as d:
        log = os.path.join(d, "calls")
        stub = os.path.join(d, "busctl")
        with open(stub, "w") as f:
            f.write(stub_body or f'#!/bin/sh\necho "$@" >> {log}\n')
        os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC)
        r = subprocess.run([SH, *args], env={**os.environ, "PATH": d + ":" + os.environ["PATH"]},
                           check=True, capture_output=True, text=True)
        if capture:
            return r.stdout
        if not os.path.exists(log):
            return ""
        with open(log) as f:
            return f.read()


class MediaSh(unittest.TestCase):
    def test_scripts_are_executable(self):  # service.luau runs media.sh directly; a lost +x silently kills the widget
        for name in ("media.sh", "spotify.py"):
            self.assertTrue(os.access(os.path.join(os.path.dirname(SH), name), os.X_OK), name)

    def test_seek_forwards_valid(self):
        self.assertIn("SetPosition ox /t/1 1000", run("seek", "org.mpris.MediaPlayer2.spotify", "/t/1", "1000"))

    def test_ctl_forwards_valid(self):  # positive case, so the rejection tests below cannot pass vacuously
        self.assertIn("Next", run("ctl", "org.mpris.MediaPlayer2.spotify", "Next"))

    def test_rejects_option_like_trackid(self):
        self.assertEqual(run("seek", "org.mpris.MediaPlayer2.spotify", "--address=x", "1000"), "")

    def test_status_survives_a_player_missing_properties(self):
        body = r'''#!/bin/sh
case "$*" in
  *list*) echo '[{"name":"org.mpris.MediaPlayer2.bad"},{"name":"org.mpris.MediaPlayer2.good"}]' ;;
  *bad*) exit 1 ;;
  *PlaybackStatus*) echo '{"type":"s","data":"Playing"}' ;;
  *Metadata*) echo '{"type":"a{sv}","data":{"xesam:title":{"type":"s","data":"T"},"xesam:artist":{"type":"s","data":"A"}}}' ;;
  *) exit 1 ;;
esac
'''
        import json
        players = json.loads(run("status", stub_body=body, capture=True))["players"]
        self.assertEqual([p["title"] for p in players if p["status"] == "Playing"], ["T"])

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
