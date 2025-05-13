#! /usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="keycloak-lab"



#  if kind cluster exist, then delete it

if kind get clusters | grep -q "$CLUSTER_NAME"; then
  echo "🗑️  Deleting existing kind cluster: $CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"
else
  echo "✅ No existing kind cluster found with name: $CLUSTER_NAME"
fi
