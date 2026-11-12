# shellcheck shell=bash
# defaults.sh — internal values that are NOT exposed as action inputs (yet).
#
# This file is the single source of truth for pipeline-controlled settings.
# Scripts must read these values as ${SBOMIT_<NAME>:-$DEFAULT_<NAME>}, so that
# promoting one to an action input later only requires adding the input in
# action.yml and mapping it to the matching SBOMIT_<NAME> env var.
#
# User-facing input defaults (sbom-format, use-syft, ...) live in action.yml,
# not here, to avoid two sources of truth.

# Tracing backend. Fixed by project policy: SBOMit does not use ptrace.
# shellcheck disable=SC2034  # consumed by scripts that source this file
DEFAULT_TRACE_BACKEND="ebpf"

# Upper bound for the traced build (minutes). Applied with coreutils `timeout`
# because composite actions cannot set a job-level timeout.
# shellcheck disable=SC2034
DEFAULT_TIMEOUT_MINUTES="30"

# witness attestors to enable (witness default). 'material' and 'product' are always recorded.
# shellcheck disable=SC2034
DEFAULT_ATTESTORS="environment,git"

# Tool install settings (versions, sources) are NOT here. Each tool keeps its
# settings at the top of its own script in scripts/install/, so changing how a
# tool is installed means editing exactly one file.
