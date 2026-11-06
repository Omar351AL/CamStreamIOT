# CamStream IoT

Live view of an IP camera on `https://camstream.omaralabed.com`.

```
Camera --Ethernet/RTSP--> Raspberry Pi (ffmpeg, no re-encode) --RTSP/TCP--> VPS MediaMTX --WebRTC--> nginx --> browser
```

## Layout
- `server/`  VPS side: MediaMTX config, systemd unit, nginx site, `install-server.sh`
- `web/`     the one-page site (WebRTC player embedded from MediaMTX)
- `pi/`      Raspberry Pi relay script, systemd unit, `relay.env.example`
- `HANDOFF_PI_SETUP.md`  how the Pi was brought up

## Server (isolated from other projects)
Everything lives in `/opt/camstream`, `/var/www/camstream`, the unit `camstream-mediamtx`
and the nginx site `camstream`. Ports used: 8554/tcp (Pi publishes), 8189/udp+tcp (WebRTC media),
8889/tcp on 127.0.0.1 only (WebRTC signalling, reached through nginx).

Deploy from a checkout on the server: `sudo bash server/install-server.sh`.
It generates the publisher password (`/opt/camstream/publisher_pass`) and the site login
(`/opt/camstream/web_login.txt`); neither is stored in this repo.

## Pi
Copy `pi/camstream-relay` to `/usr/local/bin/`, `pi/camstream-relay.service` to
`/etc/systemd/system/`, and create `/etc/camstream/relay.env` (mode 600) from `pi/relay.env.example`.
With `CAMERA_RTSP` empty the relay publishes a test pattern; set it to the camera's RTSP URL to relay the camera.

## Secrets
Never commit `relay.env`, passwords or keys (see `.gitignore`).
