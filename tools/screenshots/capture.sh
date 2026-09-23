#!/usr/bin/env bash
# Record one scenario. Frames land in <home>/frames.
#
# The widget runs inside bwrap with the fabricated home mounted at /home/dev, so
# "/home/dev/code/docs-site" is a path the collector genuinely resolves. That is
# the whole privacy argument: the screenshots cannot leak a real path because
# there is no real path in the process's view of the filesystem.
#
# Usage: capture.sh <scenario> [frame-ms] [scale]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${RIG_HOME:-$HERE/home}"
SCENARIO="$1"; FRAME_MS="${2:-50}"; SCALE="${3:-2}"
PLUGIN_ID=io.github.pedroou.agentsessionmanager

"$HERE/patch-package.py" "$HOME_DIR" "$SCENARIO" "$FRAME_MS"
rm -rf "$HOME_DIR/frames"; mkdir -p "$HOME_DIR/frames"

# plasmawindowed is a unique DBus service: a second launch would wake the first
# one and exit, silently recording the previous scenario again.
pkill -x plasmawindowed 2>/dev/null || true
sleep 0.5

# QT_QPA_PLATFORM: xcb, not offscreen. Offscreen has no GL context, so Qt falls
#   back to the software renderer, which draws rounded rectangles square - the
#   bars lose their caps.
# QT_SCALE_FACTOR: the whole zoom. grabToImage's result is multiplied by the
#   device pixel ratio, so this is what decides the resolution a glyph is
#   rasterised at rather than magnified from.
# QT_FONT_DPI: XWayland reports 144 on a scaled display, which makes every
#   label 1.5x too large relative to the layout.
# QT_STYLE_OVERRIDE is unset because a Kvantum override has no QML style module
#   and the popup fails to load entirely.
env -u QT_STYLE_OVERRIDE bwrap \
    --dev-bind / / --tmpfs /home --bind "$HOME_DIR" /home/dev \
    --setenv HOME /home/dev \
    --setenv QT_QPA_PLATFORM xcb \
    --setenv QT_FONT_DPI 96 \
    --setenv QT_SCALE_FACTOR "$SCALE" \
    --setenv QML_DISABLE_DISK_CACHE 1 \
    --setenv CLAUDE_SESSIONS_PROC /home/dev/proc \
    plasmawindowed "$PLUGIN_ID" >"$HERE/capture.log" 2>&1 &
PID=$!

# The harness writes DONE.png when its script finishes: plasmawindowed does not
# connect QQmlEngine::quit(), so it cannot close itself.
for _ in $(seq 1 250); do
    [ -f "$HOME_DIR/frames/DONE.png" ] && break
    kill -0 $PID 2>/dev/null || break
    sleep 0.2
done
sleep 0.4
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true
rm -f "$HOME_DIR/frames/DONE.png"

grep -E 'HARNESS|RIG|missing item' "$HERE/capture.log" | head -5 || true
echo "frames: $(ls "$HOME_DIR/frames" | wc -l)"
