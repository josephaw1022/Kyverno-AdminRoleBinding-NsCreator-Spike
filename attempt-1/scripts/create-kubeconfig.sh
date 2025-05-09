#!/usr/bin/env bash
# Usage:
# ./scripts/create-kubeconfig.sh \
#   --user alice \
#   --group dev-users \
#   --cluster kind-rbac-test \
#   --server https://127.0.0.1:6443 \
#   --ca certs/ca.crt \
#   --cert certs/alice.crt \
#   --key certs/alice.key \
#   --output kubeconfigs/alice.yaml

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER="$2"; shift 2 ;;
    --group) GROUP="$2"; shift 2 ;; # not embedded but useful for naming
    --cluster) CLUSTER_NAME="$2"; shift 2 ;;
    --server) SERVER="$2"; shift 2 ;;
    --ca) CA_CRT="$2"; shift 2 ;;
    --cert) USER_CRT="$2"; shift 2 ;;
    --key) USER_KEY="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${USER:-}" || -z "${CLUSTER_NAME:-}" || -z "${SERVER:-}" || -z "${CA_CRT:-}" || -z "${USER_CRT:-}" || -z "${USER_KEY:-}" || -z "${OUTPUT:-}" ]]; then
  echo "❌ Missing required argument"
  exit 1
fi

kubectl config --kubeconfig="$OUTPUT" set-cluster "$CLUSTER_NAME" \
  --server="$SERVER" \
  --certificate-authority="$CA_CRT" \
  --embed-certs=true >/dev/null

kubectl config --kubeconfig="$OUTPUT" set-credentials "$USER" \
  --client-certificate="$USER_CRT" \
  --client-key="$USER_KEY" \
  --embed-certs=true >/dev/null

kubectl config --kubeconfig="$OUTPUT" set-context "$USER" \
  --cluster="$CLUSTER_NAME" \
  --user="$USER" >/dev/null

kubectl config --kubeconfig="$OUTPUT" use-context "$USER" >/dev/null

echo "✅ Kubeconfig written to $OUTPUT for user: $USER (group: $GROUP)"
