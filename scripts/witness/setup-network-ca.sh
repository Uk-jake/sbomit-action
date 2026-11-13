#!/usr/bin/env bash
# Stage 2-2: set up the network-trace CA (only when network-trace=true)
#
# Why: witness network-trace reads HTTPS traffic with a MITM proxy. The proxy
# presents certificates for each requested host, signed by its own CA. Programs
# in the build accept them only if that CA is in their trust store; otherwise
# every HTTPS request fails with "certificate signed by unknown authority".
#
# What this script does:
#   1. Create a short-lived ECDSA P-256 CA with openssl (the same key type
#      witness generates itself). witness loads an existing PEM CA, so no
#      bootstrap `witness run` is needed, and this step needs no eBPF.
#   2. Register it in the OS trust store (update-ca-certificates).
#   3. Check that the OS CA bundle now verifies it.
# Stage 2-3 passes the same cert/key paths to witness (with generate-ca=false,
# so witness never silently creates a different, untrusted CA).
# Stage 2-4 removes the CA from the trust store after the build.
#
# Files:
#   $SBOMIT_NET_CA_KEY    CA private key (key dir, 0600, never uploaded)
#   $SBOMIT_NET_CA_CERT   CA certificate
#   $SBOMIT_NET_CA_TRUST  copy registered in the OS trust store
#
# Scope: OS trust store only. Tools that ship their own CA list (for example
# Node, Python requests/pip, Java) ignore it and are not handled yet; see the
# "Other trust stores" block below.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd openssl sudo update-ca-certificates
ensure_work_dirs
mkdir -p "$(dirname "$SBOMIT_NET_CA_CERT")"

# ── Create CA ────────────────────────────────────────────────────────────────
# Valid for 2 days: the CA only has to outlive one job.
CONF="$SBOMIT_WORK_DIR/network-ca/openssl.cnf"
cat >"$CONF" <<'EOF'
[req]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_ca
[dn]
O  = SBOMit Action
CN = SBOMit witness network-trace CA (ephemeral)
[v3_ca]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, keyCertSign, cRLSign, digitalSignature
subjectKeyIdentifier   = hash
EOF

( umask 077
  openssl req -x509 -new -config "$CONF" \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$SBOMIT_NET_CA_KEY" -out "$SBOMIT_NET_CA_CERT" -days 2 2>/dev/null
) || die "Could not create the network-trace CA with openssl."
chmod 600 "$SBOMIT_NET_CA_KEY"
chmod 644 "$SBOMIT_NET_CA_CERT"

# ── Trust CA (OS trust store) ────────────────────────────────────────────────
sudo install -m 0644 "$SBOMIT_NET_CA_CERT" "$SBOMIT_NET_CA_TRUST"
sudo update-ca-certificates >/dev/null

openssl verify -CAfile "$SBOMIT_OS_CA_BUNDLE" "$SBOMIT_NET_CA_CERT" >/dev/null 2>&1 \
  || die "The network-trace CA was added but ${SBOMIT_OS_CA_BUNDLE} does not trust it."

# ── Other trust stores ───────────────────────────────────────────────────────
# Not handled yet (to be decided per ecosystem while testing). Candidates:
#   Node:    NODE_EXTRA_CA_CERTS=$SBOMIT_NET_CA_CERT
#   Python:  REQUESTS_CA_BUNDLE / PIP_CERT=$SBOMIT_OS_CA_BUNDLE
#   Java:    keytool -importcert into the JDK cacerts
# Environment variables would be passed to the build in Stage 2-3.

fingerprint="$(openssl x509 -in "$SBOMIT_NET_CA_CERT" -noout -fingerprint -sha256 | cut -d= -f2)"
record_fact NETWORK_CA_SHA256 "$fingerprint"
log_info "Network-trace CA : ${SBOMIT_NET_CA_CERT}"
log_info "SHA-256          : ${fingerprint}"
log_info "Trusted via      : ${SBOMIT_NET_CA_TRUST} (removed again after the build)"
