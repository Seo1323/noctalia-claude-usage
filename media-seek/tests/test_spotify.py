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
    def test_playlist_covers_are_cached_and_failures_tolerated(self):
        fetched = []
        def fetch(url):
            fetched.append(url)
            if "bad" in url:
                raise OSError("down")
            return b"\xff\xd8jpeg"
        def http(method, url, headers=None, body=None):
            path = url.split("api.spotify.com/v1", 1)[1]
            if path == "/me":
                return {"id": "me"}
            if path.startswith("/me/playlists"):
                mk = lambda i, imgs: {"id": i, "name": i, "owner": {"id": "me"}, "images": imgs}
                return {"items": [mk("a", [{"url": "https://i.scdn.co/big"}, {"url": "https://i.scdn.co/small"}]),
                                  mk("b", [{"url": "https://i.scdn.co/bad"}]), mk("c", None),
                                  mk("d", [{"url": "http://insecure.example/x"}])], "next": None}
            return {"items": [], "next": None}
        api = spotify.Api("cid", self.d, http, fetch=fetch)
        got = {p["id"]: p["cover"] for p in api.playlists(TRACK)}
        self.assertTrue(got["a"] and os.path.exists(got["a"]) and got["a"].startswith(self.d))
        self.assertEqual((got["b"], got["c"], got["d"]), (None, None, None))
        self.assertEqual(fetched.count("https://i.scdn.co/small"), 1)  # smallest image, https only
        self.assertNotIn("http://insecure.example/x", fetched)
        api.playlists(TRACK)
        self.assertEqual(fetched.count("https://i.scdn.co/small"), 1)  # second call is served from the cache

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

    def test_playlists_and_items_are_paginated(self):
        pages = {}
        def http(method, url, headers=None, body=None):
            path = url.split("api.spotify.com/v1", 1)[1]
            if path == "/me":
                return {"id": "me"}
            mk = lambda i: {"id": i, "name": i, "owner": {"id": "me"}, "collaborative": False}
            if path.startswith("/me/playlists") and "offset=50" not in path:
                return {"items": [mk("p1")], "next": f"{spotify.API}/me/playlists?offset=50&limit=50"}
            if path.startswith("/me/playlists"):
                return {"items": [mk("p2")], "next": None}
            if "offset=100" not in path:  # first items page of every playlist: track is on page 2
                return {"items": [{"item": {"id": OTHER}}], "next": f"{spotify.API}{path.split('?')[0]}?offset=100&limit=100"}
            return {"items": [{"item": {"id": TRACK}}], "next": None}
        api = spotify.Api("cid", self.d, http)
        self.assertEqual({p["id"]: p["contains"] for p in api.playlists(TRACK)}, {"p1": True, "p2": True})

    def test_foreign_next_url_stops_paging_without_failing(self):
        def http(method, url, headers=None, body=None):
            path = url.split("api.spotify.com/v1", 1)[1]
            if path == "/me":
                return {"id": "me"}
            if path.startswith("/me/playlists"):
                return {"items": [{"id": "p1", "name": "p1", "owner": {"id": "me"}}], "next": None}
            return {"items": [], "next": "https://evil.example/v1/steal"}
        self.assertEqual(spotify.Api("cid", self.d, http).playlists(TRACK), [{"id": "p1", "name": "p1", "contains": False, "cover": None}])

    def test_rotated_refresh_token_is_saved(self):
        with open(os.path.join(self.d, "token.json"), "w") as f:
            json.dump({"access_token": "old", "refresh_token": "r1", "expires_at": 0}, f)
        def http(method, url, headers=None, body=None):
            if "accounts.spotify.com" in url:
                return {"access_token": "new", "refresh_token": "r2", "expires_in": 3600}
            return Fake({"mine": [], "collab": []})(method, url, headers, body)
        spotify.Api("cid", self.d, http).playlists(TRACK)
        with open(os.path.join(self.d, "token.json")) as f:
            self.assertEqual(json.load(f)["refresh_token"], "r2")

    def test_revoked_refresh_token_means_login_again(self):
        import urllib.error
        with open(os.path.join(self.d, "token.json"), "w") as f:
            json.dump({"access_token": "old", "refresh_token": "dead", "expires_at": 0}, f)
        def http(method, url, headers=None, body=None):
            raise urllib.error.HTTPError(url, 400, "invalid_grant", {}, None)
        with self.assertRaises(spotify.NotLoggedIn):
            spotify.Api("cid", self.d, http).playlists(TRACK)

    def test_token_without_refresh_token_means_login_again(self):
        with open(os.path.join(self.d, "token.json"), "w") as f:
            json.dump({"access_token": "x", "expires_at": time.time() + 3600}, f)
        with self.assertRaises(spotify.NotLoggedIn):
            self.api.playlists(TRACK)

    def test_http_errors_become_json_errors(self):
        import contextlib, io, urllib.error
        os.makedirs(os.path.join(self.d, "media-seek"))
        with open(os.path.join(self.d, "media-seek", "client_id"), "w") as f:
            f.write("cid")
        def run_main(exc):
            def boom(self, track_id):
                raise exc
            saved, spotify.Api.playlists = spotify.Api.playlists, boom
            old, os.environ["XDG_CONFIG_HOME"] = os.environ.get("XDG_CONFIG_HOME"), self.d
            try:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    spotify.main(["spotify.py", "playlists", TRACK])
                return json.loads(buf.getvalue())
            finally:
                spotify.Api.playlists = saved
                if old is None:
                    del os.environ["XDG_CONFIG_HOME"]
                else:
                    os.environ["XDG_CONFIG_HOME"] = old
        self.assertEqual(run_main(urllib.error.HTTPError("u", 403, "x", {}, None)), {"error": "http_403"})
        self.assertEqual(run_main(OSError("network down")), {"error": "OSError"})
        self.assertEqual(run_main(spotify.NotLoggedIn("x")), {"error": "not_logged_in"})

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
