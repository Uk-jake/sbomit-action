#!/usr/bin/env bash
# Stage 4-1: write run metadata
#
# Write $SBOMIT_OUT_DIR/run-metadata.json: everything needed to interpret the
# attestation and SBOM later (which runner, which tool versions, which inputs,
# how far the pipeline got). Runs even when Stage 1-3 failed.
#
# Sources:
#   - $SBOMIT_WORK_DIR/facts.env   key=value lines recorded by earlier stages (later wins)
#   - GitHub context env vars      GITHUB_REPOSITORY, GITHUB_SHA, ...
#   - action inputs                SBOMIT_* env vars (build-command is not passed here)
#
# Env:
#   SBOMIT_NETWORK_TRACE, SBOMIT_SBOM_FORMAT, SBOMIT_USE_SYFT
# Step output:
#   metadata-path
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd jq
mkdir -p "$SBOMIT_OUT_DIR"

FACTS="$SBOMIT_WORK_DIR/facts.env"
METADATA="$SBOMIT_OUT_DIR/run-metadata.json"
ATTESTATION="$SBOMIT_OUT_DIR/attestation.json"
SBOM="$(sbom_path "${SBOMIT_SBOM_FORMAT:-spdx23}")"

# How far the pipeline got, judged from the result files.
if [ -s "$SBOM" ]; then
  status="sbom_generated"
elif [ -s "$ATTESTATION" ]; then
  status="attestation_only"
else
  status="no_attestation"
fi

# facts.env -> JSON object of strings ({} when the file is missing).
facts_json='{}'
if [ -s "$FACTS" ]; then
  facts_json="$(jq -Rn '
    [inputs | select(test("^[A-Za-z_][A-Za-z0-9_]*=")) | capture("^(?<k>[^=]+)=(?<v>.*)$")]
    | reduce .[] as $f ({}; .[$f.k] = $f.v)' "$FACTS")"
fi

jq -n \
  --arg status "$status" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repository "${GITHUB_REPOSITORY:-}" \
  --arg sha "${GITHUB_SHA:-}" \
  --arg ref "${GITHUB_REF:-}" \
  --arg event "${GITHUB_EVENT_NAME:-}" \
  --arg workflow "${GITHUB_WORKFLOW:-}" \
  --arg job "${GITHUB_JOB:-}" \
  --arg run_id "${GITHUB_RUN_ID:-}" \
  --arg run_attempt "${GITHUB_RUN_ATTEMPT:-}" \
  --arg server "${GITHUB_SERVER_URL:-https://github.com}" \
  --arg action_repo "${GITHUB_ACTION_REPOSITORY:-}" \
  --arg action_ref "${GITHUB_ACTION_REF:-}" \
  --arg network_trace "${SBOMIT_NETWORK_TRACE:-}" \
  --arg sbom_format "${SBOMIT_SBOM_FORMAT:-}" \
  --arg use_syft "${SBOMIT_USE_SYFT:-}" \
  --argjson facts "$facts_json" \
  '{
     schema: "sbomit-action/run-metadata/v1",
     status: $status,
     generated_at: $generated_at,
     github: {
       repository: $repository, sha: $sha, ref: $ref, event: $event,
       workflow: $workflow, job: $job, run_id: $run_id, run_attempt: $run_attempt,
       run_url: (if $repository != "" and $run_id != "" then "\($server)/\($repository)/actions/runs/\($run_id)" else "" end),
       action: {repository: $action_repo, ref: $action_ref}
     },
     inputs: {network_trace: $network_trace, sbom_format: $sbom_format, use_syft: $use_syft},
     facts: $facts
   }' >"$METADATA"

log_info "Run metadata : ${METADATA} (status: ${status})"
set_output metadata-path "$METADATA"
