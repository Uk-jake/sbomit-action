#!/usr/bin/env bash
# Stage 4-3: write job summary
#
# Write a short, human-readable result to the run's Summary page
# ($GITHUB_STEP_SUMMARY), built only from run-metadata.json so the page and the
# uploaded metadata always agree. Prints to stdout when run outside Actions.
# Runs after the upload step so it can link to the artifact.
#
# Env:
#   SBOMIT_ARTIFACT_NAME   name of the uploaded artifact (may be empty)
#   SBOMIT_ARTIFACT_URL    download URL from actions/upload-artifact (may be empty)
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd jq

METADATA="$SBOMIT_OUT_DIR/run-metadata.json"
[ -s "$METADATA" ] || die "run-metadata.json not found. Stage 4-1 must run first."

# fact <KEY>: value from metadata facts, or "-" when not recorded.
fact() { jq -r --arg k "$1" '.facts[$k] // "-"' "$METADATA"; }

status="$(jq -r '.status' "$METADATA")"
case "$status" in
  sbom_generated)   headline="✅ SBOM generated from an eBPF-traced build" ;;
  attestation_only) headline="⚠️ Build attested, but SBOM generation did not complete" ;;
  *)                headline="❌ No attestation was produced. See the step logs for the cause" ;;
esac

# Network trace row only when it was enabled.
network_row=""
if [ "$(jq -r '.inputs.network_trace' "$METADATA")" = "true" ]; then
  network_row="| Network trace | $(fact NETWORK_CONNECTIONS) connections ($(fact NETWORK_INTERCEPTED) intercepted), $(fact NETWORK_UNIQUE_HOSTS) hosts |"
fi

artifact_name="${SBOMIT_ARTIFACT_NAME:-}"
artifact_url="${SBOMIT_ARTIFACT_URL:-}"
if [ -n "$artifact_url" ]; then
  artifact_cell="[${artifact_name}](${artifact_url})"
else
  artifact_cell="${artifact_name:--}"
fi

{
  echo "## SBOMit"
  echo
  echo "${headline}"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| SBOM | $(fact SBOM_SPEC), $(fact SBOM_PACKAGES) packages |"
  echo "| SBOM document | \`$(fact SBOM_DOCUMENT_NAME)\` version \`$(fact SBOM_DOCUMENT_VERSION)\` |"
  echo "| syft catalog | $(fact SBOM_USE_SYFT) |"
  echo "| Traced build | $(fact TRACED_PROCESSES) processes, $(fact TRACED_OPENED_FILES) opened files |"
  [ -z "$network_row" ] || echo "$network_row"
  echo "| Materials / products | $(fact ATTESTATION_MATERIALS) / $(fact ATTESTATION_PRODUCTS) |"
  echo "| Results | ${artifact_cell} |"
  echo
  echo "<details><summary>Environment and tool versions</summary>"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Runner image | $(fact RUNNER_IMAGE_OS) $(fact RUNNER_IMAGE_VERSION) |"
  echo "| Kernel | \`$(fact RUNNER_KERNEL)\` |"
  echo "| witness | \`$(fact WITNESS_SOURCE)\` |"
  echo "| go-witness | \`$(fact GO_WITNESS_SOURCE)\` |"
  echo "| sbomit | $(fact SBOMIT_VERSION) |"
  echo "| syft | $(fact SYFT_VERSION) |"
  echo "| Files returned to runner user | $(fact OWNERSHIP_RESTORED_FILES) |"
  echo
  echo "</details>"
  echo
  echo "The results artifact contains \`attestation.json\`, the SBOM, \`signing.pub\`, \`witness-run.log\` and \`run-metadata.json\`."
} >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"
