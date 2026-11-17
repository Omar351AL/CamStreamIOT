#!/bin/bash
# Installs CamStream on the VPS. Touches only /opt/camstream, /var/www/camstream,
# the camstream-* systemd units and the nginx site "camstream". Run as root from a checkout.
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

# Web login settings. Default account admin/admin unless CS_ADMIN_PASSWORD is given on first install.
if [ ! -f "$APP/web.env" ]; then
  pass="${CS_ADMIN_PASSWORD:-admin}"
  printf 'CS_USER=%s\nCS_PASS_SHA256=%s\nCS_SECRET=%s\n' "${CS_ADMIN_USER:-admin}" \
    "$(printf '%s' "$pass" | sha256sum | cut -d' ' -f1)" "$(openssl rand -hex 32)" > "$APP/web.env"
fi
chown root:camstream "$APP/web.env"; chmod 640 "$APP/web.env"
mkdir -p "$APP/web"
install -m 644 "$SRC/server/camstream-web.py" "$APP/web/app.py"
chown -R root:camstream "$APP/web"; chmod 750 "$APP/web"

# The basic-auth viewer login from the first prototype is replaced by the sign-in page.
rm -f /etc/nginx/camstream.htpasswd "$APP/web_login.txt"

# Site files: replace the whole folder so removed files do not linger.
find /var/www/camstream -mindepth 1 -delete
cp -r "$SRC/web/." /var/www/camstream/
find /var/www/camstream -type d -exec chmod 755 {} + ; find /var/www/camstream -type f -exec chmod 644 {} +

install -m 644 "$SRC/server/camstream-mediamtx.service" /etc/systemd/system/camstream-mediamtx.service
install -m 644 "$SRC/server/camstream-web.service" /etc/systemd/system/camstream-web.service
systemctl daemon-reload
systemctl enable --now camstream-mediamtx
systemctl enable camstream-web && systemctl restart camstream-web

# nginx: the TLS site once the certificate exists, otherwise the HTTP bootstrap for Certbot.
SITE=/etc/nginx/sites-available/camstream
conf="$SRC/server/nginx-camstream-bootstrap.conf"
[ -f "/etc/letsencrypt/live/$HOST/fullchain.pem" ] && conf="$SRC/server/nginx-camstream.conf"
[ -f "$SITE" ] && cp -p "$SITE" "$SITE.bak"
install -m 644 "$conf" "$SITE"
ln -sf "$SITE" /etc/nginx/sites-enabled/camstream
if nginx -t; then
  systemctl reload nginx
else
  echo "nginx test failed, restoring the previous site"
  [ -f "$SITE.bak" ] && cp -p "$SITE.bak" "$SITE" && nginx -t && systemctl reload nginx
  exit 1
fi

echo "installed: https://$HOST"
