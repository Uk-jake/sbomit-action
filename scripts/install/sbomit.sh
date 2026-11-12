#!/usr/bin/env bash
# Stage 1-2: install sbomit
#
# To change how sbomit is installed, edit only the "Install" block.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
use_tools_go   # isolated Go 1.26.x for building tools (see common.sh)

# ── Install ──────────────────────────────────────────────────────────────────
group_start "Install sbomit"
go install github.com/sbomit/sbomit@v0.3.0   # GOBIN = $SBOMIT_BIN_DIR
group_end
# ─────────────────────────────────────────────────────────────────────────────

# Record the exact version that @latest resolved to.
record_fact SBOMIT_VERSION "$(go version -m "$SBOMIT_BIN_DIR/sbomit" | awk '$1 == "mod" {print $3; exit}')"
