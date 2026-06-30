#!/usr/bin/env bash
# Fast macOS desktop iteration loop: watch dune build + auto relaunch.
#
# Usage:
#   scripts/dev-mac.sh
#
# Env overrides:
#   MAC_APP_PATH  (default _build/simulator/app/mac_app.exe)
#   SWITCH        (default simulator-5.4.1)
#   WORKSPACE     (default dune-workspace.simulator)
#
# Requires: opam switch simulator-5.4.1, dune 3.17+.

set -euo pipefail

SWITCH="${SWITCH:-simulator-5.4.1}"
WORKSPACE="${WORKSPACE:-dune-workspace.simulator}"
MAC_APP_PATH="${MAC_APP_PATH:-_build/simulator/app/mac_app.exe}"

log()  { printf '\033[35m[dev-mac]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[dev-mac]\033[0m %s\n' "$*" >&2; }

cleanup() {
  [[ -n "${WATCH_PID:-}" ]] && kill "${WATCH_PID}" 2>/dev/null || true
  [[ -n "${APP_PID:-}" ]]  && kill "${APP_PID}"  2>/dev/null || true
  rm -f /tmp/dev-mac-rebuild
  log "stopped."
}
trap cleanup EXIT INT TERM

# 1. Initial build.
log "initial build..."
opam exec --switch="${SWITCH}" -- dune build --workspace "${WORKSPACE}" "${MAC_APP_PATH}"
log "initial build ok"

# 2. Launch helper.
launch_app() {
  if [[ ! -x "${MAC_APP_PATH}" ]]; then
    warn "app not built, skipping launch"
    return
  fi
  # Kill previous instance if still running.
  [[ -n "${APP_PID:-}" ]] && kill "${APP_PID}" 2>/dev/null || true
  # Run detached; capture pid.
  "${MAC_APP_PATH}" &
  APP_PID=$!
  log "launched (pid ${APP_PID}) $(date +%H:%M:%S)"
}

# First launch.
launch_app

# 3. Watch dune build in background.
log "watching for changes... (Ctrl-C to stop)"
(
  opam exec --switch="${SWITCH}" -- dune build --watch --workspace "${WORKSPACE}" "${MAC_APP_PATH}" 2>&1 \
    | while IFS= read -r line; do
        printf '\033[2m[dune]\033[0m %s\n' "${line}"
        if [[ "${line}" == *"Success"* ]]; then
          touch /tmp/dev-mac-rebuild
        fi
      done
) &
WATCH_PID=$!

# 4. Poll for rebuild signal and relaunch.
while true; do
  if [[ -f /tmp/dev-mac-rebuild ]]; then
    rm -f /tmp/dev-mac-rebuild
    log "change detected, relaunching..."
    launch_app
  fi
  sleep 0.5
done
