// Défi : middleware qui valide LUI-MÊME un jeton Keycloak (sans oauth2-proxy).
// Vérifie : signature (clés publiques du JWKS), iss, aud, exp, puis le rôle.
import { createRemoteJWKSet, jwtVerify } from "jose";

const ISSUER = process.env.OIDC_ISSUER ?? "https://keycloak.lab.local/realms/lab";
const AUDIENCE = process.env.OIDC_AUDIENCE ?? "whoami";

// Les clés sont téléchargées une fois puis mises en cache (rotation gérée par "kid")
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/protocol/openid-connect/certs`));

export function authenticate() {
  return async (req, res, next) => {
    const header = req.headers.authorization ?? "";
    const [scheme, token] = header.split(" ");
    if (scheme !== "Bearer" || !token) {
      return res.status(401).json({ error: "jeton manquant (Authorization: Bearer ...)" });
    }
    try {
      const { payload } = await jwtVerify(token, JWKS, {
        issuer: ISSUER,          // iss
        audience: AUDIENCE,      // aud contient "whoami"
        algorithms: ["RS256"],   // refuse "none" et les algorithmes inattendus
        clockTolerance: 30,      // exp / nbf, avec 30 s de tolérance
      });
      req.user = {
        username: payload.preferred_username,
        roles: payload.realm_access?.roles ?? [],
      };
      next();
    } catch (err) {
      res.status(401).json({ error: "jeton invalide", detail: err.code ?? err.message });
    }
  };
}

export function requireRole(role) {
  return (req, res, next) =>
    req.user?.roles.includes(role)
      ? next()
      : res.status(403).json({ error: `rôle ${role} requis`, roles: req.user?.roles });
}
