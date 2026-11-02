#!/usr/bin/env bash
# Stage 2-4: remove the network-trace CA (only when network-trace=true)
#
# Runs after the build, also when it failed. Later steps in the caller's job
# must not keep trusting a CA whose key could impersonate any HTTPS site.
#   1. Remove the CA from the OS trust store and rebuild the bundle.
#   2. Delete the CA private key (no longer needed).
#   3. Check that the OS CA bundle no longer verifies the CA.
# The CA certificate is kept for reference (it is public and also recorded in
# the attestation).
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd openssl sudo update-ca-certificates

sudo rm -f "$SBOMIT_NET_CA_TRUST"
sudo update-ca-certificates >/dev/null
rm -f "$SBOMIT_NET_CA_KEY"

if [ -s "$SBOMIT_NET_CA_CERT" ] \
  && openssl verify -CAfile "$SBOMIT_OS_CA_BUNDLE" "$SBOMIT_NET_CA_CERT" >/dev/null 2>&1; then
  die "The network-trace CA is still trusted by ${SBOMIT_OS_CA_BUNDLE} after removal."
fi

log_info "Network-trace CA removed from the OS trust store and its key deleted."
