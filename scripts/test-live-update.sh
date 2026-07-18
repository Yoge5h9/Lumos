#!/bin/bash
#
# Integration test: proves the running app reflects cache writes live, with no
# relaunch — the new-user flow of `lumos setup` (empty cache) → chat with Claude
# Code (status line writes the cache) → the glow updates.
#
# It drives the actual dev binary against a disposable LUMOS_CACHE_DIR sandbox
# (never the real ~/.claude) and observes it headlessly through the LUMOS_STATE_LOG
# seam: every paint appends `<epoch> freshness=<x> state=<y> used=<z>`. The test
# asserts the app transitions from `waiting` to a live reading after a delayed
# atomic write, and tracks a second write's new percentage.
#
# Usage: scripts/test-live-update.sh
# Exit 0 on success, non-zero on failure.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/debug/lumos"

if [[ ! -x "$BIN" ]]; then
  echo "Building dev binary…"
  ( cd "$ROOT" && swift build ) || { echo "FAIL: build failed"; exit 1; }
fi

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/lumos-it.XXXXXX")"
STATE_LOG="$(mktemp "${TMPDIR:-/tmp}/lumos-state.XXXXXX.log")"
APP_PID=""

cleanup() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null
  rm -rf "$SANDBOX" "$STATE_LOG"
}
trap cleanup EXIT

# Write a valid cache.json atomically (temp file + rename over the destination),
# exactly as the status-line ingest does.
write_cache() {
  local pct="$1"
  local now uuid reset seven
  now="$(date +%s)"; uuid="$(uuidgen)"; reset=$((now + 7000)); seven=$((now + 20000))
  cat > "$SANDBOX/cache.json.tmp" <<EOF
{"$uuid":{"five_hour":{"resets_at":$reset,"used_percentage":$pct},"seven_day":{"resets_at":$seven,"used_percentage":69},"context_window":{"context_window_size":200000,"used_percentage":22},"model":"Sonnet 5","updated_at":$now}}
EOF
  mv "$SANDBOX/cache.json.tmp" "$SANDBOX/cache.json"
}

# Poll the state log for a line matching a pattern, up to a timeout (seconds).
wait_for() {
  local pattern="$1" timeout="${2:-15}" waited=0
  while (( waited < timeout )); do
    if grep -qE "$pattern" "$STATE_LOG" 2>/dev/null; then return 0; fi
    sleep 1; waited=$((waited + 1))
  done
  return 1
}

echo "Sandbox:   $SANDBOX"
echo "State log: $STATE_LOG"

LUMOS_CACHE_DIR="$SANDBOX" LUMOS_CLAUDE_DIR="$SANDBOX" LUMOS_STATE_LOG="$STATE_LOG" \
  "$BIN" >/dev/null 2>&1 &
APP_PID=$!
echo "App PID:   $APP_PID"

fail() { echo "FAIL: $1"; echo "--- state log ---"; cat "$STATE_LOG"; exit 1; }

# 1. Empty cache → the app paints the waiting state.
if ! wait_for "freshness=waiting" 10; then fail "no initial waiting paint"; fi
echo "PASS: initial state is waiting (empty cache)"

# 2. Delayed atomic write → the notch must go live within a couple seconds (watch),
#    at worst within the coarse-tick interval.
write_cache 36
if ! wait_for "freshness=live .*used=36" 15; then fail "did not go live with used=36 after first write"; fi
echo "PASS: went live (used=36) after delayed write"

# 3. A second atomic write with a new percentage must also reflect live.
write_cache 52
if ! wait_for "freshness=live .*used=52" 15; then fail "did not reflect used=52 after second write"; fi
echo "PASS: reflected used=52 after second write"

echo "ALL PASS"
exit 0
