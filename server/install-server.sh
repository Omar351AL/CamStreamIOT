#!/bin/bash
# Installs CamStream on the VPS. Touches only /opt/camstream, /var/www/camstream,
# one systemd unit and one nginx site. Run as root from the repo's server/ folder parent.
set -euo pipefail

VER="${MEDIAMTX_VERSION:-v1.21.3}"
HOST="${CAMSTREAM_HOST:-camstream.omaralabed.com}"
PUBLIC_IP="${PUBLIC_IP:-$(curl -s -4 ifconfig.me)}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/camstream

id camstream >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin camstream
mkdir -p "$APP" /var/www/camstream

if [ ! -x "$APP/mediamtx" ]; then
  tmp="$(mktemp -d)"
  base="https://github.com/bluenviron/mediamtx/releases/download/$VER"
  f="mediamtx_${VER}_linux_amd64.tar.gz"
  curl -fsSL -o "$tmp/$f" "$base/$f"
  curl -fsSL -o "$tmp/sums" "$base/checksums.sha256"
  (cd "$tmp" && grep -F "$f" sums | sed 's/ \*/  /' | sha256sum -c -)
  tar -xzf "$tmp/$f" -C "$APP" mediamtx
  rm -rf "$tmp"
fi

[ -f "$APP/publisher_pass" ] || { openssl rand -hex 16 > "$APP/publisher_pass"; chmod 600 "$APP/publisher_pass"; }
sed -e "s|__PUBLISHER_PASS__|$(cat "$APP/publisher_pass")|" -e "s|__PUBLIC_IP__|$PUBLIC_IP|" \
    "$SRC/server/mediamtx.yml" > "$APP/mediamtx.yml"
chown root:camstream "$APP/mediamtx.yml"; chmod 640 "$APP/mediamtx.yml"
chown -R root:camstream "$APP"; chmod 750 "$APP"

HTP=/etc/nginx/camstream.htpasswd
if [ ! -f "$HTP" ]; then
  pw="$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)"
  echo "viewer:$(openssl passwd -apr1 "$pw")" > "$HTP"
  chown root:www-data "$HTP"; chmod 640 "$HTP"
  printf 'user: viewer\npassword: %s\n' "$pw" > "$APP/web_login.txt"; chmod 600 "$APP/web_login.txt"
fi

install -m 644 "$SRC/web/index.html" /var/www/camstream/index.html
install -m 644 "$SRC/server/camstream-mediamtx.service" /etc/systemd/system/camstream-mediamtx.service
systemctl daemon-reload
systemctl enable --now camstream-mediamtx

install -m 644 "$SRC/server/nginx-camstream.conf" /etc/nginx/sites-available/camstream
ln -sf /etc/nginx/sites-available/camstream /etc/nginx/sites-enabled/camstream
if nginx -t; then systemctl reload nginx; else rm -f /etc/nginx/sites-enabled/camstream; echo "nginx test failed, site removed"; exit 1; fi

echo "installed. login file: $APP/web_login.txt"
