#!/usr/bin/env bash
# Fast iOS simulator iteration loop: watch dune build + auto reinstall/relaunch.
#
# Usage:
#   scripts/dev-ios.sh                 # uses booted simulator
#   scripts/dev-ios.sh "iPhone 16 Pro" # boot a specific device
#
# Env overrides:
#   BUNDLE_ID (default com.tiensonqin.todos)
#   IOS_TARGET, IOS_ARCH, IOS_SDKROOT  (defaults below)
#
# Requires: opam switch simulator-5.4.1, dune 3.17+, Xcode simctl.

set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.tiensonqin.todos}"
APP_PATH="_build/simulator.ios/app/Todos.app"
WORKSPACE="dune-workspace.simulator"
SWITCH="simulator-5.4.1"

IOS_TARGET="${IOS_TARGET:-arm64-apple-ios17.0-simulator}"
IOS_ARCH="${IOS_ARCH:-arm64}"
IOS_SDKROOT="${IOS_SDKROOT:-$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.0.sdk)}"

DEVICE_UDID=""

log()  { printf '\033[36m[dev-ios]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[dev-ios]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[dev-ios]\033[0m %s\n' "$*" >&2; }

cleanup() {
  [[ -n "${WATCH_PID:-}" ]] && kill "${WATCH_PID}" 2>/dev/null || true
  log "stopped."
}
trap cleanup EXIT INT TERM

# 1. Pick / boot a simulator.
if [[ $# -ge 1 ]]; then
  DEVICE_NAME="$1"
  log "finding simulator: ${DEVICE_NAME}"
  DEVICE_UDID=$(xcrun simctl list devices available -j \
    | /usr/bin/python3 -c "import json,sys
d=json.load(sys.stdin)
for runtime,devs in d['devices'].items():
  for dv in devs:
    if dv['name']=='${DEVICE_NAME}' and dv['isAvailable']:
      print(dv['udid']); sys.exit()
sys.exit(1)")
  log "udid: ${DEVICE_UDID}"
  xcrun simctl boot "${DEVICE_UDID}" 2>/dev/null || true
  open -a Simulator || true
else
  log "using currently booted simulator"
  DEVICE_UDID=$(xcrun simctl list devices booted -j \
    | /usr/bin/python3 -c "import json,sys
d=json.load(sys.stdin)
for runtime,devs in d['devices'].items():
  for dv in devs:
    if dv['state']=='Booted':
      print(dv['udid']); sys.exit()
sys.exit(1)" 2>/dev/null || true)
  if [[ -z "${DEVICE_UDID}" ]]; then
    err "no booted simulator. boot one or pass a device name: scripts/dev-ios.sh \"iPhone 16 Pro\""
    exit 1
  fi
  log "udid: ${DEVICE_UDID}"
fi

# 2. Initial build (fail fast before entering watch loop).
log "initial build..."
export IOS_TARGET IOS_ARCH IOS_SDKROOT
opam exec --switch="${SWITCH}" -- dune build --workspace "${WORKSPACE}" "${APP_PATH}"
log "initial build ok"

# 3. Install + launch helper.
deploy() {
  if [[ ! -d "${APP_PATH}" ]]; then
    warn "app not built yet, skipping deploy"
    return
  fi
  xcrun simctl install "${DEVICE_UDID}" "${APP_PATH}"
  xcrun simctl terminate "${DEVICE_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl launch "${DEVICE_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  log "deployed + launched $(date +%H:%M:%S)"
}

# First deploy.
deploy

# 4. Watch dune build in background; on each successful build, redeploy.
log "watching for changes... (Ctrl-C to stop)"
(
  opam exec --switch="${SWITCH}" -- dune build --watch --workspace "${WORKSPACE}" "${APP_PATH}" 2>&1 \
    | while IFS= read -r line; do
        printf '\033[2m[dune]\033[0m %s\n' "${line}"
        # Dune prints "Success" on each completed build in --watch mode.
        if [[ "${line}" == *"Success"* ]]; then
          touch /tmp/dev-ios-rebuild-"${DEVICE_UDID}"
        fi
      done
) &
WATCH_PID=$!

# 5. Poll for rebuild signal and redeploy.
while true; do
  if [[ -f /tmp/dev-ios-rebuild-"${DEVICE_UDID}" ]]; then
    rm -f /tmp/dev-ios-rebuild-"${DEVICE_UDID}"
    log "change detected, redeploying..."
    deploy
  fi
  sleep 0.5
done
