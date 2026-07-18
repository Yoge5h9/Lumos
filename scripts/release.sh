#!/usr/bin/env bash
#
# release.sh — build the prebuilt Lumos.app release artifact.
#
# Produces a universal (arm64 + x86_64), ad-hoc-signed Lumos.app packed into a
# tarball, plus its sha256. This is what the Homebrew formula downloads and
# installs directly, so users never need a compiler or the Command Line Tools —
# it works on every supported macOS (13+) regardless of their toolchain.
#
# Distribution is still Gatekeeper-free without an Apple Developer account:
# Homebrew installs formula files into the Cellar WITHOUT the quarantine xattr,
# so an ad-hoc signature is enough to run without the "unidentified developer"
# prompt. (That's why a formula-hosted binary differs from a cask .app download.)
#
# Usage:
#   scripts/release.sh            # version read from Resources/Info.plist
#   scripts/release.sh 0.1.2      # explicit version override
#
# Output:
#   dist/Lumos-<version>-universal.tar.gz   (contains Lumos.app at the root)
#   dist/Lumos-<version>-universal.tar.gz.sha256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="Lumos"
EXECUTABLE_NAME="lumos"
INFO_PLIST="Resources/Info.plist"

# --- version -------------------------------------------------------------
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
fi
echo "==> Lumos release ${VERSION}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
APP_BUNDLE="${STAGE}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

# --- 1. universal build --------------------------------------------------
# Build each slice separately and lipo them into one fat binary. We deliberately
# avoid `swift build --arch arm64 --arch x86_64`: that path drives xcbuild and
# needs full Xcode, whereas per-slice `-target` cross-compiles fine on a
# Command-Line-Tools-only machine — the same light toolchain users have.
# The macOS 13 floor is pinned in the target triple; do NOT raise it or older
# Macs crash on a missing symbol at launch.
ARM64_DIR=".build/rel-arm64"
X86_64_DIR=".build/rel-x86_64"
echo "==> Building arm64 slice..."
swift build -c release --build-path "${ARM64_DIR}" \
  -Xswiftc -target -Xswiftc arm64-apple-macos13.0
echo "==> Building x86_64 slice..."
swift build -c release --build-path "${X86_64_DIR}" \
  -Xswiftc -target -Xswiftc x86_64-apple-macos13.0

ARM64_BIN="${ARM64_DIR}/release/${EXECUTABLE_NAME}"
X86_64_BIN="${X86_64_DIR}/release/${EXECUTABLE_NAME}"
for b in "${ARM64_BIN}" "${X86_64_BIN}"; do
  [[ -x "$b" ]] || { echo "error: slice binary missing: $b" >&2; exit 1; }
done

BUILT_BINARY="${STAGE}/${EXECUTABLE_NAME}"
echo "==> Fusing universal binary with lipo..."
lipo -create -output "${BUILT_BINARY}" "${ARM64_BIN}" "${X86_64_BIN}"
ARCHS="$(lipo -archs "${BUILT_BINARY}")"
echo "    archs: ${ARCHS}"
[[ "${ARCHS}" == *arm64* && "${ARCHS}" == *x86_64* ]] \
  || { echo "error: fused binary is not universal (got: ${ARCHS})" >&2; exit 1; }

# --- 2. assemble bundle --------------------------------------------------
echo "==> Assembling ${APP_NAME}.app..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BUILT_BINARY}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp "${INFO_PLIST}" "${CONTENTS}/Info.plist"
[[ -f Resources/tips.json ]]   && cp Resources/tips.json   "${RESOURCES_DIR}/tips.json"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

# --- 3. ad-hoc sign ------------------------------------------------------
echo "==> Ad-hoc signing (codesign -s -)..."
codesign -s - --force --deep "${APP_BUNDLE}"
codesign -dv "${APP_BUNDLE}" 2>&1 | grep -E "Identifier|Signature" || true

# --- 4. tarball + checksum ----------------------------------------------
DIST_DIR="${REPO_ROOT}/dist"
mkdir -p "${DIST_DIR}"
TARBALL="${DIST_DIR}/${APP_NAME}-${VERSION}-universal.tar.gz"
echo "==> Packing ${TARBALL}..."
tar -C "${STAGE}" -czf "${TARBALL}" "${APP_NAME}.app"

SHA="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
echo "${SHA}" > "${TARBALL}.sha256"

# --- 5. homebrew bottle (:all, skip_relocation) --------------------------
# This is what actually removes the compile/CLT wall for users. Homebrew runs
# its "Command Line Tools too outdated" gate ONLY on the build-from-source path;
# pouring a bottle skips it, and a skip_relocation bottle (valid here — the
# binary is standalone, nothing Cellar-relative) needs no developer tools at
# all. The keg layout mirrors what `def install` would produce: Lumos.app + a
# bin/lumos symlink. (brew writes .brew/ and INSTALL_RECEIPT.json on pour.)
echo "==> Building Homebrew bottle..."
KEG="${STAGE}/bottle/${EXECUTABLE_NAME}/${VERSION}"
mkdir -p "${KEG}/bin"
cp -R "${APP_BUNDLE}" "${KEG}/${APP_NAME}.app"
ln -s "../${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" "${KEG}/bin/${EXECUTABLE_NAME}"
BOTTLE="${DIST_DIR}/${EXECUTABLE_NAME}-${VERSION}.all.bottle.tar.gz"
tar -C "${STAGE}/bottle" -czf "${BOTTLE}" "${EXECUTABLE_NAME}"
BSHA="$(shasum -a 256 "${BOTTLE}" | awk '{print $1}')"
echo "${BSHA}" > "${BOTTLE}.sha256"

echo
echo "==> Release artifacts ready in ${DIST_DIR}:"
echo "    plain tarball:  $(basename "${TARBALL}")  ($(du -h "${TARBALL}" | awk '{print $1}'))"
echo "      sha256: ${SHA}"
echo "    brew bottle:    $(basename "${BOTTLE}")  ($(du -h "${BOTTLE}" | awk '{print $1}'))"
echo "      sha256: ${BSHA}"
echo
echo "==> Paste into the formula's bottle block (root_url = the v${VERSION} release):"
echo "    sha256 cellar: :any_skip_relocation, all: \"${BSHA}\""
echo
echo "==> Upload both to the GitHub Release, e.g.:"
echo "    gh release create v${VERSION} \"${TARBALL}\" \"${BOTTLE}\" --repo <owner>/<repo> --title \"Lumos v${VERSION}\""
