#!/usr/bin/env python3
"""Spotify playlist helper for the media-seek plugin (stdlib only).

  spotify.py login                       one-time browser login (PKCE, no client secret)
  spotify.py playlists <track_id>        JSON: editable playlists + whether they contain the track
  spotify.py add|remove <playlist> <track_id>

Needs a Client ID in ~/.config/media-seek/client_id (Spotify dashboard app, redirect URI
http://127.0.0.1:8888/callback). Uses the February 2026 /items endpoints.
"""
import base64, hashlib, http.server, json, os, re, secrets, sys, threading, time
import urllib.error, urllib.parse, urllib.request
import webbrowser
from concurrent.futures import ThreadPoolExecutor

API = "https://api.spotify.com/v1"
ACCOUNTS = "https://accounts.spotify.com"
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "playlist-read-private playlist-read-collaborative playlist-modify-private playlist-modify-public"
MAX_PAGES = 10  # shortcut: membership is only checked in the first 1000 tracks of a playlist; raise if needed
ID_RE = re.compile(r"^[A-Za-z0-9]{22}$")        # track ids
PL_RE = re.compile(r"^[A-Za-z0-9]{1,40}$")      # playlist ids (22 in practice; only path-safe chars matter)


class NotLoggedIn(Exception):
    pass


def urlopen_json(method, url, headers=None, body=None):
    data = None
    h = dict(headers or {})
    if isinstance(body, dict) and "accounts.spotify.com" in url:
        data = urllib.parse.urlencode(body).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def check_id(value, rx=ID_RE):
    if not rx.match(value or ""):
        raise ValueError(f"bad Spotify id: {value!r}")
    return value


def check_pl(value):
    return check_id(value, PL_RE)


class Api:
    def __init__(self, client_id, config_dir, http=urlopen_json):
        self.client_id, self.dir, self.http = client_id, config_dir, http
        self.token_path = os.path.join(config_dir, "token.json")

    # ---- auth
    def _save(self, tok):
        os.makedirs(self.dir, exist_ok=True)
        fd = os.open(self.token_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(tok, f)

    def _token(self):
        try:
            with open(self.token_path) as f:
                tok = json.load(f)
        except (OSError, ValueError):
            raise NotLoggedIn("run: spotify.py login")
        if tok.get("expires_at", 0) < time.time() + 60:
            new = self.http("POST", ACCOUNTS + "/api/token", None, {
                "grant_type": "refresh_token", "refresh_token": tok["refresh_token"], "client_id": self.client_id})
            tok.update(access_token=new["access_token"], expires_at=time.time() + new.get("expires_in", 3600))
            if new.get("refresh_token"):
                tok["refresh_token"] = new["refresh_token"]
            self._save(tok)
        return tok["access_token"]

    def _call(self, method, path, body=None):
        return self.http(method, API + path, {"Authorization": "Bearer " + self._token()}, body)

    def login(self):
        verifier = secrets.token_urlsafe(64)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        state = secrets.token_urlsafe(16)
        got = {}

        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                if q.get("state") == [state] and "code" in q:
                    got["code"] = q["code"][0]
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Done - you can close this tab." if "code" in got else b"Login failed.")

            def log_message(self, *a):
                pass

        srv = http.server.HTTPServer(("127.0.0.1", 8888), H)
        srv.timeout = 180
        url = ACCOUNTS + "/authorize?" + urllib.parse.urlencode({
            "client_id": self.client_id, "response_type": "code", "redirect_uri": REDIRECT, "scope": SCOPES,
            "state": state, "code_challenge_method": "S256", "code_challenge": challenge})
        webbrowser.open(url)
        print("If no browser opened, visit:", url, file=sys.stderr)
        srv.handle_request()
        if "code" not in got:
            raise RuntimeError("login failed or timed out")
        tok = self.http("POST", ACCOUNTS + "/api/token", None, {
            "grant_type": "authorization_code", "code": got["code"], "redirect_uri": REDIRECT,
            "client_id": self.client_id, "code_verifier": verifier})
        self._save({"access_token": tok["access_token"], "refresh_token": tok["refresh_token"],
                    "expires_at": time.time() + tok.get("expires_in", 3600)})

    # ---- playlists
    def _contains(self, pid, track_id):
        path = f"/playlists/{pid}/items?limit=100&fields=items(item(id)),next"
        for _ in range(MAX_PAGES):
            page = self._call("GET", path)
            for it in page.get("items", []):
                t = it.get("item") or it.get("track")  # field was renamed in Feb 2026
                if isinstance(t, dict) and t.get("id") == track_id:
                    return True
            nxt = page.get("next")
            if not nxt:
                return False
            path = nxt.split("/v1", 1)[1]
        return False

    def playlists(self, track_id):
        check_id(track_id)
        me = self._call("GET", "/me")["id"]
        lists = [p for p in self._call("GET", "/me/playlists?limit=50").get("items", [])
                 if p["owner"]["id"] == me or p.get("collaborative")]  # others' playlists are read-only
        with ThreadPoolExecutor(8) as ex:
            flags = list(ex.map(lambda p: self._contains(check_pl(p["id"]), track_id), lists))
        return [{"id": p["id"], "name": p["name"], "contains": c} for p, c in zip(lists, flags)]

    def add(self, pid, track_id):
        self._call("POST", f"/playlists/{check_pl(pid)}/items", {"uris": [f"spotify:track:{check_id(track_id)}"]})

    def remove(self, pid, track_id):
        self._call("DELETE", f"/playlists/{check_pl(pid)}/items", {"items": [{"uri": f"spotify:track:{check_id(track_id)}"}]})


def main(argv):
    cfg = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "media-seek")
    try:
        with open(os.path.join(cfg, "client_id")) as f:
            cid = f.read().strip()
    except OSError:
        cid = ""
    if not cid:
        print(json.dumps({"error": "no_client_id"}))
        return 0
    api = Api(cid, cfg)
    try:
        cmd = argv[1] if len(argv) > 1 else ""
        if cmd == "login":
            api.login()
            print(json.dumps({"ok": True}))
        elif cmd == "playlists":
            print(json.dumps({"playlists": api.playlists(argv[2])}))
        elif cmd in ("add", "remove"):
            getattr(api, cmd)(argv[2], argv[3])
            print(json.dumps({"ok": True}))
        else:
            print(json.dumps({"error": "usage"}))
    except NotLoggedIn:
        print(json.dumps({"error": "not_logged_in"}))
    except (ValueError, IndexError):
        print(json.dumps({"error": "bad_args"}))
    except urllib.error.HTTPError as e:
        print(json.dumps({"error": f"http_{e.code}"}))
    except Exception as e:  # network down etc.: never crash the shell plugin
        print(json.dumps({"error": type(e).__name__}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
