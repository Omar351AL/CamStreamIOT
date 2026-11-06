# CamStream IoT: Raspberry Pi setup handoff (2026-11-06)

No passwords or private keys in this file.

## Verified
- Pi is a Raspberry Pi 3 Model B Rev 1.2 (read from /proc/device-tree/model).
- USB boot is already enabled: `vcgencmd otp_dump | grep 17:` gives `17:3020000a`.
- Pi boots from the USB flash when the microSD card is removed (green LED blinks, Pi appears at a new DHCP address).
- The old microSD card holds RetroPie (Raspbian 8 jessie, kernel 4.4). It takes boot priority if inserted. Its kernel cannot write the new ext4 rootfs.
- SSH to RetroPie works with a key (user `pi`), after `autostart.sh` was fixed (`systemctl enable --now` is unsupported there; use enable + start).
- Windows ICS (Wi-Fi shared to Ethernet) gives the Pi an address on 192.168.137.0/24. Needs admin to re-enable if it drops. Laptop is 192.168.137.1.

## Flash drive (disk 1, 15 GB, "AI Mass Storage" / AI210)
- Written with Raspberry Pi OS Lite 32-bit via Imager v2.0.12. Partitions bootfs (FAT) + rootfs (ext4), resized on first boot.
- The user entered a different username and hostname in Imager than planned: user `omaral351`, hostname `Omar351` (not `camstream` / `camstream-pi`). The password is forgotten (stored only as a hash).
- I edited bootfs/user-data (added my public key, NOPASSWD sudo) and set meta-data instance-id to `rpi-recover-1`. Backups: user-data.bak, meta-data.bak. After booting from the flash, cloud-init did not appear to re-run and the key was rejected. Cause not confirmed.

## Access key
- Private key: `C:\Users\OmarEE\.ssh\camstream_pi_key` (never share). Public key is ssh-ed25519 ... `claude-camstream`.

## Next step (agreed)
Re-flash the USB drive with Imager (run as Administrator): Pi 3, Raspberry Pi OS Lite 32-bit, hostname `camstream-pi`, user `camstream`, SSH with public-key authentication using the public key above. Boot with the microSD removed, wait ~5 min, find the Pi via `arp -a -N 192.168.137.1`.

## Then (from the project plan)
1. Install ffmpeg, set up eth0 for the camera and wlan0 for internet.
2. Power and configure the Dahua camera, verify RTSP.
3. Relay to the VPS (MediaMTX), then web player.
Hardening: firewall, key-only SSH, reach port 22 only via VPN/tunnel, remove NOPASSWD sudo if not needed.
