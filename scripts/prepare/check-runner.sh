#!/usr/bin/env bash
# Stage 1-1: check runner
#
# Verify the runner can execute the pipeline: Linux, x86_64, passwordless sudo,
# and the base commands used by later stages. Records runner facts.
# eBPF support is not checked here: witness fails on its own when the eBPF
# tracer cannot be loaded (see Stage 2-3).
#
# With network-trace=true, two more checks run (known requirements, not an eBPF probe):
#   - kernel 6.12 or newer (the network-trace eBPF program uses the
#     bpf_task_from_pid kfunc, added in 6.12). Without this check witness would
#     fail later with a low-level BPF load error.
#   - update-ca-certificates (Stage 2-2 registers the interception CA with it).
#
# Env:
#   SBOMIT_NETWORK_TRACE   true | false
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ensure_work_dirs

os="$(uname -s)"
arch="$(uname -m)"
kernel="$(uname -r)"
distro="unknown"
if [ -r /etc/os-release ]; then
  distro="$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
fi

problems=()

[ "$os" = "Linux" ] || problems+=("Unsupported OS '${os}'. SBOMit requires a Linux runner.")
[ "$arch" = "x86_64" ] || problems+=("Unsupported architecture '${arch}'. Only x86_64 is supported for now.")

# eBPF tracing and witness need root. Hosted runners allow sudo without a password.
if ! sudo -n true 2>/dev/null; then
  problems+=("Passwordless sudo is not available. witness needs root for eBPF tracing.")
fi

# Base commands used by later stages.
for cmd in git curl tar sha256sum make openssl jq base64 timeout; do
  command -v "$cmd" >/dev/null 2>&1 || problems+=("Required command not found: ${cmd}")
done

if [ "${SBOMIT_NETWORK_TRACE:-false}" = "true" ]; then
  # "6.8.0-1017-azure" -> major 6, minor 8
  k_major="$(printf '%s' "$kernel" | cut -d. -f1 | sed 's/[^0-9].*//')"
  k_minor="$(printf '%s' "$kernel" | cut -d. -f2 | sed 's/[^0-9].*//')"
  k_major="${k_major:-0}"; k_minor="${k_minor:-0}"
  if [ "$k_major" -lt 6 ] || { [ "$k_major" -eq 6 ] && [ "$k_minor" -lt 12 ]; }; then
    problems+=("network-trace needs Linux kernel 6.12 or newer (this runner: ${kernel}). Use a runner with a newer kernel, or set 'network-trace: false'.")
  fi
  command -v update-ca-certificates >/dev/null 2>&1 \
    || problems+=("Required command not found: update-ca-certificates (needed for network-trace). Only Ubuntu/Debian runners are supported.")
fi

if [ "${#problems[@]}" -gt 0 ]; then
  for p in "${problems[@]}"; do log_error "$p"; done
  die "Runner check failed."
fi

record_fact RUNNER_OS "$os"
record_fact RUNNER_ARCH "$arch"
record_fact RUNNER_KERNEL "$kernel"
record_fact RUNNER_DISTRO "$distro"
record_fact RUNNER_IMAGE_OS "${ImageOS:-unknown}"            # set on GitHub-hosted runners
record_fact RUNNER_IMAGE_VERSION "${ImageVersion:-unknown}"  # set on GitHub-hosted runners
# eBPF-related facts for diagnosis only (not used to decide anything).
record_fact RUNNER_BTF "$([ -f /sys/kernel/btf/vmlinux ] && echo yes || echo no)"

log_info "OS/arch : ${os}/${arch}"
log_info "Kernel  : ${kernel}"
log_info "Distro  : ${distro}"
log_info "Image   : ${ImageOS:-unknown} ${ImageVersion:-unknown}"
log_info "BTF     : $([ -f /sys/kernel/btf/vmlinux ] && echo yes || echo no)"
