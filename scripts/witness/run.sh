#!/usr/bin/env bash
# Stage 2-3: run witness
#
# Run the user's build under witness with eBPF file tracing (and, with
# network-trace=true, network tracing) and write a signed attestation to
# $SBOMIT_OUT_DIR/attestation.json.
#
# To change HOW witness is invoked, edit only the "Run" block.
#
# After the run this script verifies that eBPF tracing was really used:
#   - on failure : explain likely causes (eBPF unavailable, timeout, build error)
#   - on success : require "Using tracer: ebpf" in the log and >= 1 traced process
#                  network-trace=true: require network trace data (0 connections only warns)
# (There is no separate eBPF check step. witness fails before the build starts
#  when the eBPF tracer cannot be loaded; it never falls back to ptrace.)
#
# Env:
#   SBOMIT_BUILD_COMMAND   the user's build command (never interpolated into code)
#   SBOMIT_NETWORK_TRACE   true | false
# Step output:
#   attestation-path
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd witness jq base64 timeout
[ -n "${SBOMIT_BUILD_COMMAND:-}" ] || die "SBOMIT_BUILD_COMMAND is empty."
[ -f "$SBOMIT_KEY_DIR/signing.key" ] || die "Signing key not found. Stage 2-1 must run first."

BACKEND="${SBOMIT_TRACE_BACKEND:-$DEFAULT_TRACE_BACKEND}"
ATTESTORS="${SBOMIT_ATTESTORS:-$DEFAULT_ATTESTORS}"
TIMEOUT_MINUTES="${SBOMIT_TIMEOUT_MINUTES:-$DEFAULT_TIMEOUT_MINUTES}"
NETWORK_TRACE="${SBOMIT_NETWORK_TRACE:-false}"
ATTESTATION="$SBOMIT_OUT_DIR/attestation.json"
LOG="$SBOMIT_WORK_DIR/witness-run.log"

cd "$SBOMIT_WORKSPACE"
mkdir -p "$SBOMIT_OUT_DIR"

# network-trace options. The CA from Stage 2-2 is passed explicitly and
# generate-ca=false makes witness fail instead of creating an untrusted CA.
network_args=()
if [ "$NETWORK_TRACE" = "true" ]; then
  if [ ! -s "$SBOMIT_NET_CA_CERT" ] || [ ! -s "$SBOMIT_NET_CA_KEY" ]; then
    die "Network-trace CA not found. Stage 2-2 must run first."
  fi
  ATTESTORS="${ATTESTORS},network-trace"
  network_args=(
    --experimental
    --attestor-network-trace-ca-cert-path "$SBOMIT_NET_CA_CERT"
    --attestor-network-trace-ca-key-path "$SBOMIT_NET_CA_KEY"
    --attestor-network-trace-generate-ca=false
  )
fi

# Timestamp marker: files created/modified by the root-run build are newer than this.
MARKER="$SBOMIT_WORK_DIR/build-start.marker"
touch "$MARKER"

# ── Run ──────────────────────────────────────────────────────────────────────
# Root is required for eBPF. HOME and PATH are kept so the build sees the same
# toolchains and caches as the runner user (sudo would otherwise reset them).
# Output goes to the Actions log and to $LOG (for the checks below).
group_start "witness run (backend: ${BACKEND}, network-trace: ${NETWORK_TRACE}, timeout: ${TIMEOUT_MINUTES}m)"
set +e
sudo -E env "HOME=$HOME" "PATH=$PATH" \
  timeout --kill-after=30s "${TIMEOUT_MINUTES}m" \
  witness run \
    --step build \
    --trace \
    --attestor-command-run-trace-backend "$BACKEND" \
    --attestations "$ATTESTORS" \
    "${network_args[@]}" \
    --signer-file-key-path "$SBOMIT_KEY_DIR/signing.key" \
    --outfile "$ATTESTATION" \
    -- bash -c "$SBOMIT_BUILD_COMMAND" 2>&1 | tee "$LOG"
rc="${PIPESTATUS[0]}"
set -e
group_end
# ─────────────────────────────────────────────────────────────────────────────

# ---- Return files to the runner user ----------------------------------------
# The build ran as root, so build outputs (workspace) and caches ($HOME, e.g.
# ~/go, ~/.cache) it created are root-owned. Later steps in the caller's job run
# as the runner user and would fail with "permission denied" on them.
# Only files that are root-owned AND created/changed after the marker (ctime,
# which tools cannot backdate the way they can mtime) are changed, so
# anything root-owned before this action is left as it was. Runs on success
# and failure alike.
owner="$(id -u):$(id -g)"
restored="$(sudo find "$SBOMIT_WORKSPACE" "$HOME" "$SBOMIT_WORK_DIR" -xdev -user root -cnewer "$MARKER" \
  -print -exec chown -h "$owner" {} + 2>/dev/null | sort -u | wc -l)" || restored="?"
log_info "Returned ${restored} root-owned file(s) created by the build to the runner user."
record_fact OWNERSHIP_RESTORED_FILES "$restored"
record_fact WITNESS_EXIT_CODE "$rc"

# Keep the witness log with the uploaded results (success or failure) for diagnosis.
cp "$LOG" "$SBOMIT_OUT_DIR/witness-run.log" 2>/dev/null || true

# ---- Failure: explain the most likely cause --------------------------------
if [ "$rc" -ne 0 ]; then
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    die "witness run timed out after ${TIMEOUT_MINUTES} minutes."
  fi
  # The eBPF tracer is loaded BEFORE the build starts. If witness logged that the
  # tracer is in use, eBPF worked and the failure came from the build itself.
  if ! grep -q "Using tracer: ebpf" "$LOG" && grep -qiE 'ebpf|bpf|cgroup' "$LOG"; then
    # TODO: refine this message once the supported runner image is confirmed by E2E.
    die "witness could not use eBPF tracing on this runner (kernel $(uname -r)). SBOMit requires eBPF; ptrace is not supported. See the witness log above."
  fi
  # The tracer loaded but reported an internal error while reading events.
  # go-witness then kills the build on purpose (an incomplete trace must not be signed).
  if grep -q "command-run eBPF trace error" "$LOG"; then
    die "witness eBPF tracer reported an internal tracing error (see 'command-run eBPF trace error' above). This is a witness/go-witness issue, not a build failure. Known to happen on kernel 7.0 (this runner: $(uname -r))."
  fi
  # HTTPS inside the build rejected the interception CA (network-trace only).
  if [ "$NETWORK_TRACE" = "true" ] && grep -qiE 'certificate signed by unknown authority|self[- ]signed certificate in certificate chain|unable to get local issuer certificate|SELF_SIGNED_CERT_IN_CHAIN|PKIX path building failed' "$LOG"; then
    die "An HTTPS client in the build did not trust the network-trace CA (see the certificate error above). Only the OS trust store is configured; tools with their own CA list (for example Node, Python requests/pip, Java) are not supported yet."
  fi
  die "witness run failed (exit code ${rc}). This is usually the build command itself failing; see the log above."
fi

# ---- Success: verify eBPF tracing was really used --------------------------
grep -q "Using tracer: ebpf" "$LOG" \
  || die "witness finished but did not report 'Using tracer: ebpf'. The attestation was not produced with eBPF tracing."

[ -s "$ATTESTATION" ] || die "witness finished but ${ATTESTATION} is missing or empty."

# Decode the DSSE envelope once and summarize what was captured.
statement="$SBOMIT_WORK_DIR/attestation.statement.json"
jq -r '.payload' "$ATTESTATION" | base64 -d >"$statement" || die "Could not decode the attestation payload."
count() { jq "$1" "$statement"; }
processes="$(count '[.predicate.attestations[] | select(.type | test("/command-run/")) | .attestation.processes // [] | length] | add // 0')"
opened_files="$(count '[.predicate.attestations[] | select(.type | test("/command-run/")) | .attestation.processes // [] | .[] | .openedfiles // {} | length] | add // 0')"
materials="$(count '[.predicate.attestations[] | select(.type | test("/material/")) | .attestation // {} | length] | add // 0')"
products="$(count '[.predicate.attestations[] | select(.type | test("/product/")) | .attestation // {} | length] | add // 0')"

[ "$processes" -gt 0 ] || die "The attestation contains no traced processes. eBPF tracing did not capture the build."

# Network trace: the data sits under a "network_trace" object (the network-trace
# attestor). Searched anywhere in the attestations so a layout change upstream
# does not silently read as "no data".
if [ "$NETWORK_TRACE" = "true" ]; then
  nt_count="$(count '[.predicate.attestations[].attestation | .. | objects | select(has("network_trace"))] | length')"
  [ "$nt_count" -gt 0 ] || die "network-trace was enabled but the attestation contains no network trace data."
  nt='[.predicate.attestations[].attestation | .. | objects | select(has("network_trace")) | .network_trace]'
  connections="$(count "${nt} | map(.summary.total_connections // (.connections // [] | length)) | add // 0")"
  intercepted="$(count "${nt} | map(.summary.intercepted_count // 0) | add // 0")"
  hosts="$(count "${nt} | map(.summary.unique_hosts // []) | (add // []) | unique | length")"
  record_fact NETWORK_CONNECTIONS "$connections"
  record_fact NETWORK_INTERCEPTED "$intercepted"
  record_fact NETWORK_UNIQUE_HOSTS "$hosts"
  log_info "Connections    : ${connections} (${intercepted} intercepted, ${hosts} hosts)"
  if [ "$connections" -eq 0 ]; then
    log_warn "network-trace recorded 0 connections. The build may not use the network (for example, dependencies restored from a cache)."
  fi
fi

record_fact TRACED_PROCESSES "$processes"
record_fact TRACED_OPENED_FILES "$opened_files"
record_fact ATTESTATION_MATERIALS "$materials"
record_fact ATTESTATION_PRODUCTS "$products"

log_info "Attestation    : ${ATTESTATION}"
log_info "Processes      : ${processes}"
log_info "Opened files   : ${opened_files}"
log_info "Materials      : ${materials}"
log_info "Products       : ${products}  (known witness limitation: often empty when tracing is on)"

set_output attestation-path "$ATTESTATION"
