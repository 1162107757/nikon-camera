#!/bin/sh
# Called from the extracted, SHA-verified site archive. No CloudBase credential is stored on this server.
set -eu
phase=${1:-stage}
bundle=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
base=/var/www/huevia-home
release="$base/releases/20261107-v1"
mkdir -p "$base/releases"
if [ ! -f /etc/caddy/huevia.caddy.before-homepage-20261107 ]; then
    cp -p /etc/caddy/huevia.caddy /etc/caddy/huevia.caddy.before-homepage-20261107
fi
if [ ! -e "$release" ]; then mkdir "$release"; fi
cp -R "$bundle/home/." "$release/"
find "$release" -type d -exec chmod 755 {} \;
find "$release" -type f -exec chmod 644 {} \;
ln -sfn "$release" "$base/current.pending"
mv -Tf "$base/current.pending" "$base/current"
if [ "$phase" = stage ]; then candidate="$bundle/huevia.stage.caddy";
elif [ "$phase" = activate ]; then candidate="$bundle/huevia.caddy";
else echo 'Unknown phase'; exit 1; fi
cp -p /etc/caddy/huevia.caddy /etc/caddy/huevia.caddy.pre-phase
cp "$candidate" /etc/caddy/huevia.caddy
if ! caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
    cp /etc/caddy/huevia.caddy.pre-phase /etc/caddy/huevia.caddy
    exit 1
fi
if ! systemctl reload caddy; then
    cp /etc/caddy/huevia.caddy.pre-phase /etc/caddy/huevia.caddy
    systemctl reload caddy
    exit 1
fi
printf 'HUEVIA_PHASE=%s\n' "$phase"
systemctl is-active caddy
sha256sum /etc/caddy/huevia.caddy "$release/index.html"
