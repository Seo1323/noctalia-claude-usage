"""spotify.py: playlist membership / add / remove against a fake Spotify (no network)."""
import json, os, sys, tempfile, time, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import spotify  # noqa: E402

TRACK = "A" * 22
OTHER = "B" * 22


class Fake:
    """Records calls; serves /me, /me/playlists and /playlists/<id>/items."""

    def __init__(self, items):
        self.items, self.calls = items, []  # items: {playlist_id: [track ids]}

    def __call__(self, method, url, headers=None, body=None):
        self.calls.append((method, url, body))
        path = url.split("api.spotify.com/v1", 1)[1]
        if path == "/me":
            return {"id": "me"}
        if path.startswith("/me/playlists"):
            return {"items": [
                {"id": "mine", "name": "Mine", "owner": {"id": "me"}, "collaborative": False},
                {"id": "theirs", "name": "Theirs", "owner": {"id": "x"}, "collaborative": False},
                {"id": "collab", "name": "Collab", "owner": {"id": "x"}, "collaborative": True},
            ], "next": None}
        if "/items" in path and method == "GET":
            pid = path.split("/")[2]
            return {"items": [{"item": {"id": t}} for t in self.items[pid]], "next": None}
        return {"snapshot_id": "s"}


class Spotify(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        with open(os.path.join(self.d, "token.json"), "w") as f:
            json.dump({"access_token": "tok", "refresh_token": "r", "expires_at": time.time() + 3600}, f)
        os.chmod(os.path.join(self.d, "token.json"), 0o600)
        self.api = spotify.Api(client_id="cid", config_dir=self.d, http=Fake({"mine": [TRACK], "collab": [OTHER]}))

    def test_only_editable_playlists_with_membership(self):
        got = {p["id"]: p["contains"] for p in self.api.playlists(TRACK)}
        self.assertEqual(got, {"mine": True, "collab": False})  # "theirs" is read-only, so hidden

    def test_add_uses_items_endpoint_with_uri(self):
        self.api.add("collab", TRACK)
        m, url, body = self.api.http.calls[-1]
        self.assertEqual((m, body), ("POST", {"uris": [f"spotify:track:{TRACK}"]}))
        self.assertTrue(url.endswith("/playlists/collab/items"))

    def test_remove_uses_items_endpoint(self):
        self.api.remove("mine", TRACK)
        m, url, body = self.api.http.calls[-1]
        self.assertEqual((m, body), ("DELETE", {"items": [{"uri": f"spotify:track:{TRACK}"}]}))
        self.assertTrue(url.endswith("/playlists/mine/items"))

    def test_rejects_malformed_ids(self):
        for bad in ("../x", "A" * 21, "A" * 22 + "?"):
            with self.assertRaises(ValueError):
                self.api.add("mine", bad)
        with self.assertRaises(ValueError):
            self.api.add("mine/../me", TRACK)
        self.assertFalse(any(c[0] in ("POST", "DELETE") for c in self.api.http.calls))

    def test_missing_login_is_a_clear_error(self):
        os.remove(os.path.join(self.d, "token.json"))
        with self.assertRaises(spotify.NotLoggedIn):
            self.api.playlists(TRACK)

    def test_expired_token_is_refreshed(self):
        with open(os.path.join(self.d, "token.json"), "w") as f:
            json.dump({"access_token": "old", "refresh_token": "r", "expires_at": 0}, f)
        calls = []
        def http(method, url, headers=None, body=None):
            calls.append(url)
            if "accounts.spotify.com" in url:
                return {"access_token": "new", "expires_in": 3600}
            return Fake({"mine": [], "collab": []})(method, url, headers, body)
        spotify.Api(client_id="cid", config_dir=self.d, http=http).playlists(TRACK)
        self.assertIn("accounts.spotify.com", calls[0])
        with open(os.path.join(self.d, "token.json")) as f:
            tok = json.load(f)
        self.assertEqual((tok["access_token"], tok["refresh_token"]), ("new", "r"))  # refresh token kept


if __name__ == "__main__":
    unittest.main()
