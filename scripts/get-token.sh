#!/usr/bin/env bash
# Partie 4 : jeton de bob via le flux "password" (Direct access grants activé TEMPORAIREMENT).
# Usage : CLIENT_SECRET=xxx USER_PW=yyy ./scripts/get-token.sh [bob]
set -euo pipefail
U=${1:-bob}
: "${CLIENT_SECRET:?Définir CLIENT_SECRET}" "${USER_PW:?Définir USER_PW}"
curl -s https://keycloak.lab.local/realms/lab/protocol/openid-connect/token \
  -d grant_type=password -d client_id=whoami -d client_secret="$CLIENT_SECRET" \
  -d username="$U" -d password="$USER_PW" | jq -r '.access_token // .'
