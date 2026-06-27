<div align="center">

<img src="web/assets/lapsus.png" alt="LAPSUS" width="120" />

**Community-powered local AI p2p network**

<h1>LAPSUS coordinator</h1>

<em>The thin server that introduces peers — it never sees your prompts.</em>

<a href="https://lapsus.pyrates.io">lapsus.pyrates.io</a> &nbsp;·&nbsp; <a href="https://github.com/pythononwheels/lapsus-app">client app</a> &nbsp;·&nbsp; <a href="LICENSE">AGPL-3.0</a>

</div>

---

This is the **LAPSUS coordinator** — the thin server that makes the peer-to-peer
network work. It does three things and nothing more:

- **Discovery** — online peers announce the models they share (with context length + multimodal capability).
- **Signaling** — relays WebRTC offer/answer/ICE so two peers can open a direct channel.
- **Credits** — books mutually-signed receipts into a Compute-Credit ledger (SQLite).

It **never sees prompts or answers** — those flow directly peer to peer over an
encrypted channel. The client app lives in
[lapsus-app](https://github.com/pythononwheels/lapsus-app).

## Run a coordinator

```bash
cp .env.example .env          # set SECRET_KEY_BASE (mix phx.gen.secret) and PHX_HOST
docker compose -f docker-compose.prod.yml up -d --build
curl http://127.0.0.1:4000/health      # → ok
```

Put it behind a TLS reverse proxy that upgrades WebSockets (e.g. Caddy:
`reverse_proxy localhost:4000`). Agents then connect at `wss://<your-host>`, and
the static homepage is served from `web/`. The credit ledger is a SQLite DB on a
named volume — back it up.

## What's inside

- `apps/lapsus_coordinator` — Phoenix app: discovery, signaling relay, ledger.
- `apps/lapsus_core` — shared identity (Ed25519, self-authenticating peer IDs),
  Compute-Credits, mutually-signed receipts.
- `web/` — the public homepage (static).

Anyone can run a coordinator — that's the point. Run your own, or join the one at
`lapsus.pyrates.io`.

## License

[AGPL-3.0](LICENSE). Network copyleft — run a modified version as a service, share
your source. A commons, not a land-grab.
