# Défi : middleware JWT Express

```bash
cd defi/express-jwt && npm install
NODE_EXTRA_CA_CERTS=../../lab-ca.crt npm start      # faire confiance à la CA de lab

# Jeton de alice (admin) puis de bob (developer), Direct access grants activé temporairement
TOKEN=$(CLIENT_SECRET=... USER_PW=... ../../scripts/get-token.sh alice)
curl -s -X POST localhost:3000/api/admin -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"a":1}'   # 200
TOKEN=$(CLIENT_SECRET=... USER_PW=... ../../scripts/get-token.sh bob)
curl -s -X POST localhost:3000/api/admin -H "Authorization: Bearer $TOKEN"     # 403
curl -s -X POST localhost:3000/api/admin                                        # 401
```
