#!/usr/bin/env bash
# Stage 1-2: install syft
#
# Downloads a pinned syft release and verifies it against a SHA-256 pinned in
# this file (no installer script, nothing runs as root). The binary goes to
# $SBOMIT_BIN_DIR, which is never added to the user's PATH (see common.sh).
#
# To change the syft version, edit SYFT_VERSION and SYFT_SHA256 together. The
# hash is the linux_amd64.tar.gz line of syft_<version>_checksums.txt on the
# release page: https://github.com/anchore/syft/releases
#
# For a one-off test of another version without editing this file, set
# SBOMIT_SYFT_VERSION (and SBOMIT_SYFT_SHA256). Without a pinned hash, the
# release's checksums.txt is used instead and a warning is printed.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ── Version ──────────────────────────────────────────────────────────────────
DEFAULT_SYFT_VERSION="1.57.1"
DEFAULT_SYFT_SHA256="bf52519eb57f675d47c07d43213cb6dff6449f3d6d1147ff6701ed91f44eef0c"
SYFT_VERSION="${SBOMIT_SYFT_VERSION:-$DEFAULT_SYFT_VERSION}"
if [ "$SYFT_VERSION" = "$DEFAULT_SYFT_VERSION" ]; then
  SYFT_SHA256="${SBOMIT_SYFT_SHA256:-$DEFAULT_SYFT_SHA256}"
else
  SYFT_SHA256="${SBOMIT_SYFT_SHA256:-}"
fi
# ─────────────────────────────────────────────────────────────────────────────

# ── Install ──────────────────────────────────────────────────────────────────
group_start "Install syft ${SYFT_VERSION}"
base="https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}"
tarball="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
dl_dir="${SBOMIT_TOOLS_DIR}/syft-download"
rm -rf "$dl_dir"
mkdir -p "$dl_dir" "$SBOMIT_BIN_DIR"
cd "$dl_dir"

curl -fsSLO "${base}/${tarball}"
if [ -n "$SYFT_SHA256" ]; then
  echo "${SYFT_SHA256}  ${tarball}" | sha256sum -c -
else
  log_warn "No pinned SHA-256 for syft ${SYFT_VERSION}; verifying against the release's checksums.txt only."
  curl -fsSLO "${base}/syft_${SYFT_VERSION}_checksums.txt"
  grep " ${tarball}\$" "syft_${SYFT_VERSION}_checksums.txt" | sha256sum -c -
fi
tar -xzf "$tarball" syft
install -m 0755 syft "$SBOMIT_BIN_DIR/syft"
cd "$SBOMIT_TOOLS_DIR"
rm -rf "$dl_dir"
group_end
# ─────────────────────────────────────────────────────────────────────────────

record_fact SYFT_VERSION "$("$SBOMIT_BIN_DIR/syft" version | awk '/^Version:/ {print $2}')"
