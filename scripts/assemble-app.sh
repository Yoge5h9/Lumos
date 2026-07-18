#!/usr/bin/env bash
#
# assemble-app.sh — build Lumos and hand-assemble Lumos.app.
#
# Builds the `lumos` executable via SPM (no Xcode project, no full Xcode
# dependency) and packs it into a minimal, ad-hoc-signed .app bundle:
#
#   Lumos.app/
#     Contents/
#       Info.plist
#       MacOS/lumos
#       Resources/
#
# Idempotent: safe to re-run; it rebuilds and re-assembles from scratch each
# time rather than patching a stale bundle.
#
# Usage:
#   scripts/assemble-app.sh [output-dir]
#
# Env overrides:
#   BUILD_CONFIG   swift build configuration (default: release)
#   APP_NAME       bundle display/file name, without .app (default: Lumos)
#   SKIP_BUILD     if set to "1", skip `swift build` and reuse the existing binary

set -euo pipefail

# --- paths -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_CONFIG="${BUILD_CONFIG:-release}"
APP_NAME="${APP_NAME:-Lumos}"
EXECUTABLE_NAME="lumos"
OUTPUT_DIR="${1:-${REPO_ROOT}/.build/app}"

APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

INFO_PLIST_SRC="${REPO_ROOT}/Resources/Info.plist"
TIPS_JSON_SRC="${REPO_ROOT}/Resources/tips.json"
BUILT_BINARY="${REPO_ROOT}/.build/${BUILD_CONFIG}/${EXECUTABLE_NAME}"

echo "==> Lumos.app assembly"
echo "    repo root:      ${REPO_ROOT}"
echo "    build config:   ${BUILD_CONFIG}"
echo "    output bundle:  ${APP_BUNDLE}"

# --- 1. build ------------------------------------------------------------
if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
  echo "==> Skipping build (SKIP_BUILD=1); expecting existing binary at:"
  echo "    ${BUILT_BINARY}"
else
  echo "==> Building with 'swift build -c ${BUILD_CONFIG}'..."
  (cd "${REPO_ROOT}" && swift build -c "${BUILD_CONFIG}")
fi

if [[ ! -x "${BUILT_BINARY}" ]]; then
  echo "error: built binary not found at ${BUILT_BINARY}" >&2
  echo "       did 'swift build -c ${BUILD_CONFIG}' produce the '${EXECUTABLE_NAME}' product?" >&2
  exit 1
fi

if [[ ! -f "${INFO_PLIST_SRC}" ]]; then
  echo "error: Info.plist not found at ${INFO_PLIST_SRC}" >&2
  exit 1
fi

# --- 2. assemble bundle skeleton ------------------------------------------
echo "==> Assembling bundle skeleton..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Copying executable..."
cp "${BUILT_BINARY}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "==> Copying Info.plist..."
cp "${INFO_PLIST_SRC}" "${CONTENTS_DIR}/Info.plist"

echo "==> Copying tips.json..."
if [[ -f "${TIPS_JSON_SRC}" ]]; then
  cp "${TIPS_JSON_SRC}" "${RESOURCES_DIR}/tips.json"
else
  # Not fatal: NotificationEngine falls back to its embedded default tips when
  # tips.json is absent, so a bundle without it still runs correctly.
  echo "    warning: ${TIPS_JSON_SRC} not found; app will fall back to embedded default tips"
fi

echo "==> Copying AppIcon.icns..."
APPICON_SRC="${REPO_ROOT}/Resources/AppIcon.icns"
if [[ -f "${APPICON_SRC}" ]]; then
  cp "${APPICON_SRC}" "${RESOURCES_DIR}/AppIcon.icns"
else
  echo "    warning: ${APPICON_SRC} not found; bundle will use the generic app icon"
fi

# --- 3. ad-hoc sign --------------------------------------------------------
# Ad-hoc signing (`-s -`) only: no Apple Developer account, no notarization.
# This is deliberate per DISTRIBUTION.md — the whole point of the source-build
# route is to avoid Gatekeeper/notarization entirely.
echo "==> Ad-hoc signing (codesign -s -)..."
codesign -s - --force --deep "${APP_BUNDLE}"

echo "==> Done. Bundle ready at:"
echo "    ${APP_BUNDLE}"
