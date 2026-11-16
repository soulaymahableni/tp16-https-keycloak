# TP16 : réponses aux questions

## Chaîne de confiance TLS

* La **CA** de lab possède une clé privée (Secret `lab-ca`, champ `tls.key`) et un certificat autosigné (`ca.crt`). On installe **seulement le certificat public** dans les magasins de confiance (VM, navigateur, Pod oauth2-proxy).
* Le **ClusterIssuer `lab-ca`** signe avec cette clé les certificats demandés par les Ingress. Le client vérifie la chaîne : certificat du site → signé par « Lab CA TP16 » → présent dans son magasin de confiance → connexion acceptée.
* Le **SAN** (Subject Alternative Name) liste les noms DNS couverts (`DNS:whoami.lab.local`). Les navigateurs ignorent le CN : sans le bon SAN, le certificat est refusé.
* La **clé privée de la CA** ne doit jamais sortir du cluster : quiconque la possède peut fabriquer un certificat « valide » pour n'importe quel nom (y compris `google.com`) sur toutes les machines qui font confiance à la CA, et intercepter le trafic (attaque de l'homme du milieu).
* Pourquoi pas Let's Encrypt ? ACME exige de prouver le contrôle d'un **domaine public** (défi HTTP-01 ou DNS-01). `*.lab.local` n'existe pas sur Internet, d'où une CA interne, comme pour les services internes d'une entreprise.

## Partie 1 : cert-manager

* `selfsigned` (ClusterIssuer) ne sert qu'à **créer la CA** : le Certificate `lab-ca` (`isCA: true`) est signé par lui-même.
* `lab-ca` (ClusterIssuer de type `ca`) utilise le Secret `lab-ca`. Pour un ClusterIssuer, ce Secret est lu dans le namespace de cert-manager.
* Chaîne d'objets : annotation sur l'Ingress → **Certificate** → **CertificateRequest** (CSR) → signature par l'Issuer → **Secret TLS** (`tls.crt`, `tls.key`, `ca.crt`) → utilisé par Traefik.

## Partie 2 : Ingress HTTPS

* `curl -v` affiche `issuer: O=DevOps Lab; CN=Lab CA TP16` et `SSL certificate verify ok`, car la CA est dans `/etc/ssl/certs` de la VM.
* SAN : `DNS:whoami.lab.local`. Validité : 90 jours (`cert-manager.io/duration: 2160h`).
* **Suppression du Secret `whoami-tls`** : cert-manager détecte l'écart entre le Certificate (état désiré) et le Secret absent. Il crée une nouvelle CertificateRequest et **recrée le Secret** en quelques secondes. Traefik recharge le nouveau certificat sans redémarrage.
* **Renouvellement anticipé** : champ `spec.renewBefore` du Certificate (ici `720h`, via l'annotation `cert-manager.io/renew-before`). cert-manager renouvelle 30 jours avant l'expiration ; `status.renewalTime` donne la date prévue. Par défaut, il renouvelle aux deux tiers de la durée de validité.

## Partie 3 : Keycloak

* Keycloak tourne derrière Traefik, qui termine le TLS : `KC_HOSTNAME=https://keycloak.lab.local` (URL publique utilisée dans les jetons, le claim `iss`) et `KC_PROXY_HEADERS=xforwarded` (Keycloak fait confiance aux en-têtes `X-Forwarded-*`).
* `start-dev` + base H2 sur un PVC : suffisant pour le lab. En production : mode `start`, base PostgreSQL externe, plusieurs replicas.
* **DNS interne** (`05-coredns-custom.yaml`) : les Pods ne voient pas `/etc/hosts` de la VM. Le nom `keycloak.lab.local` est réécrit vers le Service Traefik (`traefik.kube-system.svc.cluster.local`) : oauth2-proxy passe par l'Ingress HTTPS, avec le même nom et le même certificat que le navigateur. Aucune IP de nœud à adapter.

## Partie 4 : realm, rôles, client, JWT

* **Authentification** = prouver *qui* on est (login Keycloak). **Autorisation** = décider *ce qu'on a le droit de faire* (rôle `developer` ou `admin` exigé par oauth2-proxy).
* **OAuth 2.0** délègue l'autorisation : le client obtient un **access_token** pour appeler une API. **OpenID Connect** ajoute l'authentification par-dessus : un **id_token** (JWT) qui décrit l'utilisateur, la découverte (`.well-known/openid-configuration`), le JWKS et `userinfo`.
* **Client confidentiel** (`Client authentication: On`) : oauth2-proxy tourne côté serveur et peut garder un secret. Le flux **Standard flow** (authorization code + PKCE) évite que les jetons passent par l'URL du navigateur.
* **Mapper Audience** : sans lui, `aud` ne contient que `account`. oauth2-proxy (et le middleware du défi) vérifient que le jeton leur est bien destiné (`aud` contient `whoami`), sinon un jeton émis pour une autre application serait accepté.
* **Claims du jeton de bob** :
  * `iss` = `https://keycloak.lab.local/realms/lab` (qui a émis le jeton) ;
  * `aud` = `["whoami", "account"]` (pour qui) ;
  * `exp` = date d'expiration (5 min par défaut pour l'access token) ;
  * `realm_access.roles` = `["developer", "default-roles-lab", …]`.
* Un JWT est seulement **signé**, pas chiffré : n'importe qui peut le décoder (base64url). Sa sécurité repose sur la **signature RS256**, vérifiable avec la clé publique du `jwks_uri`. On n'y met donc jamais de secret.
* Le flux **password** (Direct access grants) fait passer le mot de passe par l'application : il est déconseillé (supprimé dans OAuth 2.1). D'où sa désactivation après l'observation.

## Partie 5 : oauth2-proxy

* Flux : navigateur → Traefik → oauth2-proxy (pas de cookie) → **302** vers Keycloak → login → retour sur `/oauth2/callback?code=…` → oauth2-proxy échange le code contre les jetons (avec le client secret), vérifie la signature, `iss`, `aud` et le **rôle**, pose un cookie chiffré → proxifie vers whoami.
* **alice / bob** : accès autorisé. whoami reçoit `X-Forwarded-User` / `X-Forwarded-Email`, et la réponse contient `X-Auth-Request-User` / `X-Auth-Request-Email` (`--set-xauthrequest`). L'application n'a pas été modifiée.
* **carol** (rôle `user` seulement) : authentifiée, mais **pas autorisée** → **403**. C'est bien la différence entre authentification et autorisation.
* **Déconnexion** : `/oauth2/sign_out` supprime seulement le **cookie d'oauth2-proxy**. La **session SSO Keycloak** (cookie `KEYCLOAK_SESSION` sur `keycloak.lab.local`) existe toujours : à la visite suivante, Keycloak renvoie immédiatement un nouveau code sans redemander le mot de passe. C'est le principe du SSO : une connexion pour toutes les applications du realm. Pour une vraie déconnexion, il faut aussi appeler l'`end_session_endpoint` de Keycloak (RP-initiated logout, par exemple `--rd=` vers `/protocol/openid-connect/logout`), ou fermer la session dans la console Keycloak.

## Défi : middleware Express

`defi/express-jwt/auth.js` (bibliothèque `jose`) :
* télécharge et met en cache les clés publiques du **JWKS** de Keycloak (choix de la clé par `kid`) ;
* vérifie la **signature** (RS256 uniquement, ce qui refuse `alg: none`), `iss`, `aud` (`whoami`) et `exp` ;
* `requireRole("admin")` protège `POST /api/admin`.

Tests réalisés avec des jetons signés : admin → 200, developer → 403, sans jeton → 401, mauvais `aud` → 401, jeton expiré → 401.
