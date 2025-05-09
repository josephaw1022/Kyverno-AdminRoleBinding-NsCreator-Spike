#!/usr/bin/env bash

USERNAME="$1"
cat <<EOF
{
  "apiVersion": "client.authentication.k8s.io/v1",
  "status": {
    "user": {
      "username": "$USERNAME"
    },
    "token": "fake-token-for-$USERNAME"
  }
}
EOF
