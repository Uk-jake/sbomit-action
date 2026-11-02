#!/usr/bin/env bash
# Stage 0-1: validate action inputs before installing anything.
#
# Env (set by action.yml from inputs):
#   SBOMIT_BUILD_COMMAND   required, non-blank (multi-line allowed)
#   SBOMIT_NETWORK_TRACE   true | false
#   SBOMIT_SBOM_FORMAT     spdx23 | cdx14 | cdx15
#   SBOMIT_USE_SYFT        true | false
#
# Behavior: collects every problem and reports them all at once, then exits 1.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ALLOWED_SBOM_FORMATS=(spdx23 cdx14 cdx15)

build_command="${SBOMIT_BUILD_COMMAND:-}"
network_trace="${SBOMIT_NETWORK_TRACE:-}"
sbom_format="${SBOMIT_SBOM_FORMAT:-}"
use_syft="${SBOMIT_USE_SYFT:-}"

errors=()

# build-command: must contain at least one non-whitespace character.
if [ -z "${build_command//[[:space:]]/}" ]; then
  errors+=("'build-command' is required. Example: build-command: go build -trimpath ./...")
fi

# network-trace
if ! is_bool "$network_trace"; then
  errors+=("'network-trace' must be 'true' or 'false' (got: '${network_trace}')")
fi

# sbom-format
if ! is_one_of "$sbom_format" "${ALLOWED_SBOM_FORMATS[@]}"; then
  errors+=("'sbom-format' must be one of: ${ALLOWED_SBOM_FORMATS[*]} (got: '${sbom_format}')")
fi

# use-syft
if ! is_bool "$use_syft"; then
  errors+=("'use-syft' must be 'true' or 'false' (got: '${use_syft}')")
fi

# Combination rule: sbomit fails with a multi-root CycloneDX error for cdx15 + syft catalog.
# Remove this rule once the upstream issue is fixed.
if [ "$sbom_format" = "cdx15" ] && [ "$use_syft" = "true" ]; then
  errors+=("'sbom-format: cdx15' cannot be combined with 'use-syft: true' (known sbomit multi-root CycloneDX error). Use 'sbom-format: spdx23' or set 'use-syft: false'.")
fi

if [ "${#errors[@]}" -gt 0 ]; then
  for e in "${errors[@]}"; do
    log_error "$e"
  done
  die "Input validation failed with ${#errors[@]} error(s)."
fi

group_start "Validated inputs"
log_info "network-trace : ${network_trace}"
log_info "sbom-format   : ${sbom_format}"
log_info "use-syft      : ${use_syft}"
log_info "build-command :"
printf '%s\n' "$build_command" | sed 's/^/    /'
group_end
