#!/usr/bin/env bash
# BagIdea Office — Linux Tier-1 launcher. Launches the native shell, which spawns
# AND OWNS the Node daemon + the Godot office — so quitting from the tray tears the
# whole stack down (no orphaned daemon left holding :8787). This mirrors how
# `bagidea start` and the login-autostart entry launch the office.
#
# NOTE: do NOT start the daemon separately here. An earlier version backgrounded
# `node server.js &` before exec'ing the shell; the shell then saw a daemon already
# running, never took ownership of it, and so couldn't stop it on quit — leaving the
# daemon alive on :8787 after the wallpaper closed (GitHub #28).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SHELL_BIN="$ROOT/shell/target/release/bagidea-office-shell"

if [ ! -x "$SHELL_BIN" ]; then
  echo "Shell not built at $SHELL_BIN — run ./build-linux.sh first." >&2
  exit 1
fi

# If a daemon is ALREADY up (e.g. a stale one from a previous run), the shell will
# reuse it but won't own it — so it can't stop it on quit. Tell the user how to
# clear that case rather than silently orphaning it again.
if curl -s -m2 http://127.0.0.1:8787/ -o /dev/null; then
  echo "[run-linux] a daemon is already running on :8787 — the shell will reuse it."
  echo "[run-linux] if it lingers after you quit, run: bagidea stop"
fi

echo "[run-linux] launching office (the shell starts + owns the daemon and Godot)…"
exec "$SHELL_BIN" "$@"
