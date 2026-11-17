#!/usr/bin/env python3
"""CamStream web backend (stdlib only).

Serves the login session (HMAC-signed cookie) and camera status for the dashboard.
nginx calls /auth/check via auth_request to guard the pages, /api/ and the video (/cam/).
Settings come from /opt/camstream/web.env (see install-server.sh).
"""
import hashlib
import hmac
import json
import os
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

USER = os.environ.get("CS_USER", "admin")
PASS_SHA256 = os.environ["CS_PASS_SHA256"]
SECRET = os.environ["CS_SECRET"].encode()
TTL = int(os.environ.get("CS_SESSION_HOURS", "12")) * 3600
MTX_API = os.environ.get("CS_MTX_API", "http://127.0.0.1:9997")
LISTEN = ("127.0.0.1", int(os.environ.get("CS_PORT", "8410")))
COOKIE = "cs_session"

CAMERAS = [
    {"id": "camera1", "name": "Camera 01", "location": "Site A, outdoor",
     "model": "Dahua IPC-HDW2449T-S-IL"},
]

# Simple brute-force brake: per-IP failed logins within a window.
FAILS = {}
MAX_FAILS, WINDOW = 10, 600


def make_token(user):
    payload = f"{user}|{int(time.time()) + TTL}"
    mac = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}|{mac}"


def session_user(cookie_header):
    for part in (cookie_header or "").split(";"):
        name, _, value = part.strip().partition("=")
        if name != COOKIE:
            continue
        try:
            user, exp, mac = value.split("|")
        except ValueError:
            return None
        good = hmac.new(SECRET, f"{user}|{exp}".encode(), hashlib.sha256).hexdigest()
        if hmac.compare_digest(mac, good) and int(exp) > time.time():
            return user
    return None


def camera_status(cam_id):
    try:
        with urllib.request.urlopen(f"{MTX_API}/v3/paths/get/{cam_id}", timeout=2) as r:
            p = json.load(r)
    except Exception:
        return {"online": False, "since": None, "tracks": [], "viewers": 0}
    return {
        "online": bool(p.get("ready")),
        "since": p.get("readyTime"),
        "tracks": p.get("tracks") or [],
        "viewers": len(p.get("readers") or []),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "CamStream"

    def log_message(self, fmt, *args):
        pass

    def client_ip(self):
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def send_json(self, code, body, cookie=None):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        user = session_user(self.headers.get("Cookie"))
        if self.path == "/auth/check":
            self.send_response(204 if user else 401)
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif not user:
            self.send_json(401, {"error": "unauthorized"})
        elif self.path == "/api/me":
            self.send_json(200, {"user": user})
        elif self.path == "/api/cameras":
            self.send_json(200, {"cameras": [dict(c, **camera_status(c["id"])) for c in CAMERAS]})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/auth/logout":
            self.send_json(200, {"ok": True},
                           f"{COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0")
            return
        if self.path != "/auth/login":
            self.send_json(404, {"error": "not found"})
            return

        ip, now = self.client_ip(), time.time()
        recent = [t for t in FAILS.get(ip, []) if now - t < WINDOW]
        if len(recent) >= MAX_FAILS:
            self.send_json(429, {"error": "Too many attempts. Try again in a few minutes."})
            return

        raw = self.rfile.read(min(int(self.headers.get("Content-Length") or 0), 4096)).decode(errors="replace")
        if "json" in (self.headers.get("Content-Type") or ""):
            try:
                form = json.loads(raw or "{}")
            except ValueError:
                form = {}
        else:
            form = {k: v[0] for k, v in parse_qs(raw).items()}
        user, password = str(form.get("username", "")), str(form.get("password", ""))

        ok = hmac.compare_digest(user, USER) and hmac.compare_digest(
            hashlib.sha256(password.encode()).hexdigest(), PASS_SHA256)
        if not ok:
            FAILS[ip] = recent + [now]
            self.send_json(401, {"error": "Incorrect username or password."})
            return
        FAILS.pop(ip, None)
        self.send_json(200, {"ok": True},
                       f"{COOKIE}={make_token(user)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age={TTL}")


if __name__ == "__main__":
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
