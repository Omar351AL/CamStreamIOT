# CamStream IoT

Live view of an IP camera on `https://camstream.omaralabed.com`.

```
Camera --Ethernet/RTSP--> Raspberry Pi (ffmpeg, no re-encode) --SRT (or RTSP/TCP)--> VPS MediaMTX --WebRTC--> nginx --> browser
```

## Layout
- `server/`  VPS side: MediaMTX config, login backend (`camstream-web.py`), systemd units, nginx site, `install-server.sh`
- `web/`     the site: sign-in page, camera dashboard, live view (own WHEP player), brand assets
- `pi/`      Raspberry Pi relay script, systemd unit, `relay.env.example`
- `HANDOFF_PI_SETUP.md`  how the Pi was brought up

## Server (isolated from other projects)
Everything lives in `/opt/camstream`, `/var/www/camstream`, the units `camstream-mediamtx` and
`camstream-web`, and the nginx site `camstream`. Public ports: 8554/tcp (RTSP publish), 8890/udp (SRT publish),
8189/udp+tcp (WebRTC media). Local only: 8889 (WebRTC signalling), 9997 (MediaMTX API), 8410 (login backend).

Deploy from a checkout on the server: `sudo bash server/install-server.sh`.
It generates the publisher password (`/opt/camstream/publisher_pass`) and the login settings
(`/opt/camstream/web.env`: user, password hash, session secret); neither is stored in this repo.
The prototype account is `admin` / `admin` (set `CS_ADMIN_PASSWORD` on first install, or edit
`CS_PASS_SHA256` in `web.env` and restart `camstream-web`, to change it).

nginx guards every page, `/api/` and `/cam/` with `auth_request` against the backend's session cookie;
only `/login.html`, `/assets/` and `/auth/` are public.

## Pi
Copy `pi/camstream-relay` to `/usr/local/bin/`, `pi/camstream-relay.service` to
`/etc/systemd/system/`, and create `/etc/camstream/relay.env` (mode 600) from `pi/relay.env.example`.
With `CAMERA_RTSP` empty the relay publishes a test pattern; set it to the camera's RTSP URL to relay the camera.

## Secrets
Never commit `relay.env`, passwords or keys (see `.gitignore`).

## Pi network
- `wlan0` joins the Wi-Fi/hotspot and carries all internet traffic (default route).
- `eth0` is dedicated to the camera and static (no DHCP): `192.168.50.1/24` and `192.168.1.50/24`
  (the Dahua factory address is `192.168.1.108`). Without a DHCP server, a DHCP-configured eth0 gets dropped.
- Set the camera credentials with `sudo camstream-set-camera` (reads the password silently, forces H.264, restarts the relay).
- To reach the camera's web UI from a laptop: `ssh -L 18080:192.168.1.108:80 -N <user>@<pi>` then open http://127.0.0.1:18080/.

## Pi Wi-Fi and setup hotspot
- The Pi joins saved Wi-Fi networks automatically (the original `omar` hotspot is saved as an open network).
- If no saved network is reachable for 90 s, `camstream-wifi-watch` starts the hotspot `CamStream-Setup`
  (WPA2; its password is in `/etc/camstream/setup-hotspot.txt` on the Pi). The Pi is `10.42.0.1` on it.
  While nobody is connected, it retries the saved networks every 5 minutes.
- To save a new network or password: connect to `CamStream-Setup`, then
  `ssh -t -i ~/.ssh/camstream_pi_key omaral351@10.42.0.1 camstream-set-wifi`.
