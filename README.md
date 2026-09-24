# mmo-cr-backend-local

Local Backend-as-a-Service (BaaS) environment for `mmo-cr` frontend and integration developers.

This repository orchestrates the independent backend services below, each of which owns its
own Docker Compose configuration and remains fully runnable on its own:

```text
mmo-cr-backend-local/
├── compose.yml                        # root orchestration (this file)
├── compose/floci/start.d/             # combined AWS emulator bootstrap scripts (see below)
├── mmo-cr-authentication-service/
│   ├── .env                           # local config for this service (see below)
│   └── compose.yml
└── mmo-cr-reference-data-service/
    ├── .env                           # local config for this service (see below)
    └── compose.yml
```

## Prerequisites

- Docker Desktop (or an equivalent Docker Engine) with **Docker Compose v2.24+** (this setup
  uses the top-level `include:` field and the `!override` merge tag). Check with
  `docker compose version`.

## 1. Configure each service's `.env`

Every service reads its configuration from its own `.env` file (mounted read-only into its
container). All values have safe local defaults (see each service's `src/config.js`), but the
table below documents what to set for the two services to work together locally.

### `mmo-cr-authentication-service/.env`

This service is a local always-allow authentication stub (see
[docs/adr/0001-remove-mongodb-from-server-bootstrap.md](mmo-cr-authentication-service/docs/adr/0001-remove-mongodb-from-server-bootstrap.md))
with no external dependencies. An **empty file is fine** — every value defaults sensibly
(`HOST=0.0.0.0`, `PORT=3001`). There's nothing to change for local orchestration.

### `mmo-cr-reference-data-service/.env`

Copy `.env.sample` to `.env` if it doesn't already exist, then confirm/set these keys so the
service can reach Floci (the local S3 emulator) and the authentication service **as containers
on the shared Docker network** (not via `localhost`/`host.docker.internal`):

| Variable | Local value | Why |
| --- | --- | --- |
| `AWS_ENDPOINT_URL` | `http://localhost:4566` | Used when running one-off host commands (e.g. `npm run reference-data:bootstrap` from your machine). The root `compose.yml` overrides this to `http://floci:4566` for the containerised app itself, via `mmo-cr-reference-data-service/compose.yml`'s `environment:` block. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `test` / `test` | Dummy credentials Floci accepts locally. |
| `REFERENCE_DATA_BUCKET` | `mmo-cr-reference-data-service` | Must match the bucket the bootstrap script seeds. |
| `AUTHENTICATION_SERVICE_URL` | `http://mmo-cr-authentication-service:3001` | Must use the **Compose service name and internal container port**, not a host-published port — both services talk to each other over the `cdp-tenant` Docker network, never via the host. |

All other keys (`PORT`, `LOG_LEVEL`, `REFERENCE_DATA_*`, etc.) can keep their `.env.sample`
defaults.

## 2. Start all services

From the repository root:

```bash
docker compose up -d
```

This builds/starts every service defined by the included `compose.yml` files on the shared
`cdp-tenant` Docker network, so services can reach each other by container/service name
(e.g. `http://mmo-cr-authentication-service:3001`, `http://floci:4566`).

Follow logs with `docker compose logs -f`.

### 3. Seed reference data (first run only)

Floci starts empty, so the reference-data-service's cache hydration will fail until the
committed seed data is loaded into it:

```bash
docker compose exec mmo-cr-reference-data-service npm run reference-data:bootstrap
docker compose restart mmo-cr-reference-data-service
```

Floci persists its data to the `floci-data` volume, so you only need to do this once — it
survives `docker compose down`/`up` and container restarts. You only need to repeat it after
`docker compose down -v` or `npm run floci:reset`.

### 4. Verify everything is up

```bash
curl -s http://localhost:3004/health | jq                    # authentication service
curl -s http://localhost:3002/health | jq                    # reference data service
curl -s http://localhost:3002/health/ready | jq              # confirms all datasets hydrated
curl -s http://localhost:3002/health/dependencies | jq       # per-dependency status
```

`health/ready` should report `"ready": true` with all 6 mandatory datasets loaded.

### Ports

| Service | Host port | Container port |
| --- | --- | --- |
| `mmo-cr-authentication-service` | 3004 | 3001 |
| `mmo-cr-reference-data-service` | 3002 | 3001 |
| `floci` (shared AWS emulator) | 4566 | 4566 |

Both app services listen on the same internal container port (`3001`) — that's harmless since
each runs in its own container network namespace. Only the host port mappings need to differ,
which is why they're remapped above.

## Stopping all services

```bash
docker compose down
```

Add `-v` (`docker compose down -v`) to also remove the named volumes (`floci-data`) if you want
a completely clean slate — you'll need to re-run the seed step above afterwards.

## Adding a new backend service in future

1. Add the new service's repository under this workspace with its own `compose.yml`.
2. Add its path to the `include:` list in the root `compose.yml`.
3. Make sure its own `compose.yml` attaches it to the `cdp-tenant` network (`networks:
   - cdp-tenant`) so it's reachable by service name from the others. If it doesn't declare one
   itself, add a root-level `networks:` override for it instead of editing its file.
4. Only if it collides with an existing service name or host port, add a minimal override for
   just that field under the root `compose.yml`'s `services:` block (use the `!override` tag on
   lists so they're replaced rather than merged) — do not duplicate the rest of that service's
   configuration.

## Architectural decisions

- **`include:` over multiple `-f` flags**: the Compose Specification's top-level `include:`
  field (Compose v2.20+) is designed for exactly this use case — composing independently
  maintained projects without copying their service definitions into a shared file. It keeps
  each service's `compose.yml` as its single source of truth.
- **Shared `cdp-tenant` network**: declaring it once at the root keeps the name authoritative
  and lets every included service resolve each other by service name. Not every service
  declares this network in its own `compose.yml` (e.g. the authentication service has no local
  dependencies of its own), so the root file adds a minimal `networks:` override for those
  cases rather than editing the service's file.
- **Shared `floci` (AWS emulator)**: both services independently declare a `floci` service.
  Compose merges same-named services from included files, so they run as a single shared
  container rather than two competing instances on the same host port (`4566`). Their startup
  scripts both mount to the same container path, so a small root-level directory
  (`compose/floci/start.d/`) combines both services' init scripts (renamed with numeric
  prefixes to run in a defined order) and is used to override the merged volume — this is the
  one exception to "no duplication", required because Compose can't merge two directories onto
  one bind-mount target.
- **Reference-data service port remap**: both services listen on container port `3001`. The
  reference-data service's host mapping is overridden to `3002:3001` via the root `compose.yml`
  so both can run at the same time without touching either service's own `compose.yml`.
- **Cross-service calls use Docker service names, not `localhost`/`host.docker.internal`**:
  since both services are containers on the same Docker network, they should address each other
  by Compose service name and internal container port (e.g.
  `http://mmo-cr-authentication-service:3001`). Routing through the host adds an unnecessary
  hop and breaks if host port mappings ever change.

## Troubleshooting

- **`Authentication Service is not configured.`** — `AUTHENTICATION_SERVICE_URL` is unset/empty
  in `mmo-cr-reference-data-service/.env`, or the container hasn't been restarted since you
  last edited it (Node only reads `--env-file` once, at process start).
- **`Authentication Service is unavailable.`** — the reference-data-service container can't
  reach the URL configured. Confirm it points at
  `http://mmo-cr-authentication-service:3001` (not `localhost`/`host.docker.internal`), and
  that both containers are on the `cdp-tenant` network: `docker network inspect cdp-tenant`.
- **`dataset_not_found` / hydration failures** — Floci hasn't been seeded yet; run the bootstrap
  command in [step 3](#3-seed-reference-data-first-run-only).

