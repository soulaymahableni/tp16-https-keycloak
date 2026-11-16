#!/usr/bin/env bash
# Décode la partie "payload" d'un JWT (base64url, sans padding) et affiche les claims utiles.
# Usage : ./scripts/decode-jwt.sh "$TOKEN"     ou     echo "$TOKEN" | ./scripts/decode-jwt.sh
set -euo pipefail
T=${1:-$(cat)}
P=$(echo -n "$T" | cut -d. -f2 | tr '_-' '/+')
while [ $(( ${#P} % 4 )) -ne 0 ]; do P="$P="; done
echo "$P" | base64 -d | jq '{iss, aud, azp, exp, exp_date: (.exp | todate), preferred_username, email, realm_access}'
