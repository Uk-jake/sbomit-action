#!/usr/bin/env bash
# Stage 1-2: install witness
#
# To change WHICH witness is built, edit the "Source" block (repo URL and
# branch / tag / commit). Forks and development branches work too.
# To change HOW it is built, edit the "Install" block.
#
# Each Source value can also be overridden with an env var for a one-off test
# on a VM without editing this file, for example:
#   SBOMIT_GO_WITNESS_REF=my-feature-branch bash scripts/install/witness.sh
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
use_tools_go   # isolated Go 1.26.x for building tools (see common.sh)

# ── Source ───────────────────────────────────────────────────────────────────
WITNESS_REPO="${SBOMIT_WITNESS_REPO:-https://github.com/in-toto/witness.git}"
WITNESS_REF="${SBOMIT_WITNESS_REF:-main}"
GO_WITNESS_REPO="${SBOMIT_GO_WITNESS_REPO:-https://github.com/in-toto/go-witness.git}"
GO_WITNESS_REF="${SBOMIT_GO_WITNESS_REF:-main}"
# ─────────────────────────────────────────────────────────────────────────────

# ── Install ──────────────────────────────────────────────────────────────────
group_start "Install witness"
cd "$SBOMIT_TOOLS_DIR"
rm -rf witness go-witness

git clone "$WITNESS_REPO" witness
git -C witness checkout "$WITNESS_REF"
git clone "$GO_WITNESS_REPO" go-witness
git -C go-witness checkout "$GO_WITNESS_REF"

cd witness
go work init .
go work use ../go-witness

make build
install -m 0755 ./bin/witness "$SBOMIT_BIN_DIR/witness"
group_end
# ─────────────────────────────────────────────────────────────────────────────

# Show and record exactly what was built (branch names move, commit SHAs do not).
log_info "witness    : ${WITNESS_REPO} ${WITNESS_REF} -> $(git -C "$SBOMIT_TOOLS_DIR/witness" rev-parse HEAD)"
log_info "go-witness : ${GO_WITNESS_REPO} ${GO_WITNESS_REF} -> $(git -C "$SBOMIT_TOOLS_DIR/go-witness" rev-parse HEAD)"
record_fact WITNESS_SOURCE "${WITNESS_REPO} ${WITNESS_REF} $(git -C "$SBOMIT_TOOLS_DIR/witness" rev-parse HEAD)"
record_fact GO_WITNESS_SOURCE "${GO_WITNESS_REPO} ${GO_WITNESS_REF} $(git -C "$SBOMIT_TOOLS_DIR/go-witness" rev-parse HEAD)"
