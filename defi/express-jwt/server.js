import express from "express";
import { authenticate, requireRole } from "./auth.js";

const app = express();
app.use(express.json());

app.get("/api/public", (_req, res) => res.json({ ok: true }));
app.get("/api/me", authenticate(), (req, res) => res.json(req.user));
app.post("/api/admin", authenticate(), requireRole("admin"), (req, res) =>
  res.json({ ok: true, by: req.user.username, body: req.body }),
);

app.listen(3000, () => console.log("API sur http://localhost:3000"));
