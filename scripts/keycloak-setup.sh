#!/usr/bin/env bash
# OPTION RAPIDE (Partie 4) : crée realm, rôles, utilisateurs et client avec kcadm.
# La méthode attendue reste l'interface web ; ce script sert à rattraper une erreur
# ou à reconstruire le realm. Usage :
#   LAB_PW='MotDePasse!123' ./scripts/keycloak-setup.sh
set -euo pipefail
LAB_PW=${LAB_PW:?Définir LAB_PW (mot de passe des utilisateurs alice, bob, carol)}
ADMIN_PW=$(kubectl -n keycloak get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)

kc() { kubectl -n keycloak exec deploy/keycloak -- /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }

kc config credentials --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PW"

kc create realms -s realm=lab -s enabled=true || echo "(realm lab déjà présent)"

for r in user developer admin; do
  kc create roles -r lab -s name=$r || echo "(rôle $r déjà présent)"
done

declare -A ROLE=( [alice]=admin [bob]=developer [carol]=user )
for u in alice bob carol; do
  kc create users -r lab -s username=$u -s enabled=true -s email=$u@lab.local \
     -s emailVerified=true -s firstName=${u^} -s lastName=Lab || echo "(utilisateur $u déjà présent)"
  kc set-password -r lab --username $u --new-password "$LAB_PW"       # non temporaire
  kc add-roles -r lab --uusername $u --rolename ${ROLE[$u]}
done

CID=$(kc get clients -r lab -q clientId=whoami --fields id --format csv --noquotes || true)
if [ -z "$CID" ]; then
  CID=$(kc create clients -r lab -i -s clientId=whoami -s enabled=true \
        -s publicClient=false -s standardFlowEnabled=true \
        -s directAccessGrantsEnabled=false -s implicitFlowEnabled=false \
        -s serviceAccountsEnabled=false \
        -s 'redirectUris=["https://whoami.lab.local/oauth2/callback"]' \
        -s 'webOrigins=["https://whoami.lab.local"]')
  # Mapper Audience : "whoami" dans le claim aud (équivalent du scope whoami-dedicated)
  kc create clients/$CID/protocol-mappers/models -r lab \
     -s name=audience-whoami -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
     -s 'config."included.client.audience"=whoami' \
     -s 'config."access.token.claim"=true' -s 'config."id.token.claim"=true'
fi

echo
echo "Client whoami : id interne $CID"
echo -n "Client secret : "
kc get clients/$CID/client-secret -r lab --fields value --format csv --noquotes
