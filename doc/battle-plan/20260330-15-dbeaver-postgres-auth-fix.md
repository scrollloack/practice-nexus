# 15 — DBeaver PostgreSQL Auth Error Fix (Local Postgres Conflict)

## Concept: Why the Auth Error Happens

Running `ss -tlnp | grep 5432` reveals a **local PostgreSQL is bound to
`127.0.0.1:5432`**. This instance intercepts any connection to `localhost:5432`
before Docker even gets a chance to handle it. The local instance has a
different password for the `postgres` user, so DBeaver gets:

```
FATAL: password authentication failed for user "postgres"
```

The Docker `db` container (`postgres:16-alpine`) is healthy and reachable, but
not via `localhost:5432` — it lives at its own internal Docker bridge IP
(`172.18.0.2`).

---

## Credentials (from `docker-compose.yml`)

| Field    | Value               |
|----------|---------------------|
| Username | `postgres`          |
| Password | `password`          |
| Database | `nexus_development` |

---

## Option A — Connect via Docker Container IP (WSL terminal only)

> **Windows DBeaver users: skip to Option B or C.**
> `172.18.0.2` is a Docker internal bridge IP. It is only routable from
> within WSL2 itself — Windows cannot reach it, causing a **connection timeout**.

The Docker `db` container is reachable at its internal IP from a WSL terminal
(e.g., `psql` or a DBeaver instance running inside WSL). No service needs to
be stopped.

**Docker container IP:** `172.18.0.2`

Set the connection to:

| Setting  | Value               |
|----------|---------------------|
| Host     | `172.18.0.2`        |
| Port     | `5432`              |
| Database | `nexus_development` |
| Username | `postgres`          |
| Password | `password`          |
| SSL      | Disabled            |

> **Note:** The container IP can change when the container is recreated.
> Re-run the command below if the connection stops working after a restart.

```bash
docker inspect practice-nexus-db-1 \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

---

## Option B — Stop the Local PostgreSQL and Use localhost (Recommended)

Stopping the local PostgreSQL frees port 5432, allowing Docker Desktop's port
forwarding to route `localhost:5432` correctly to the Docker container — from
both Windows and WSL.

```bash
# Stop and disable the local Postgres service in WSL
sudo systemctl stop postgresql
sudo systemctl disable postgresql   # optional: prevent auto-start on WSL boot
```

Verify port 5432 is no longer held by local Postgres:

```bash
ss -tlnp | grep 5432
# Should show nothing — Docker Desktop handles the mapping transparently
```

Then connect DBeaver (on Windows) to:

| Setting  | Value               |
|----------|---------------------|
| Host     | `localhost`         |
| Port     | `5432`              |
| Database | `nexus_development` |
| Username | `postgres`          |
| Password | `password`          |
| SSL      | Disabled            |

To re-enable the local Postgres later:

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

---

## Option C — Remap Docker to a Different Port (Keep Both Running)

If you need both Postgres instances running at the same time, map Docker's
Postgres to a different host port so there is no conflict.

In `docker-compose.yml`, change the `db` service ports:

```yaml
ports:
  - "5433:5432"   # was "5432:5432"
```

Restart the service:

```bash
docker compose up -d --force-recreate db
```

Then connect DBeaver (on Windows) to:

| Setting  | Value               |
|----------|---------------------|
| Host     | `localhost`         |
| Port     | `5433`              |
| Database | `nexus_development` |
| Username | `postgres`          |
| Password | `password`          |
| SSL      | Disabled            |

> **Important:** `5433` is only the host-side mapping. Inside Docker, the `db`
> container still listens on `5432`. The Rails app must connect on `5432` via
> Docker's internal network — not the host port. Add `DB_PORT: 5432` explicitly
> to `web` and `worker` in `docker-compose.yml` to prevent `database.yml`
> from defaulting to the wrong port.

```yaml
# web and worker environment blocks
environment:
  DB_HOST: db
  DB_PORT: 5432      # <-- required when host port differs from container port
  DB_USERNAME: postgres
  DB_PASSWORD: password
```

Restart affected containers after the change:

```bash
docker compose up -d --force-recreate web worker
```

---

## Problem — Rails app gets `ActiveRecord::ConnectionNotEstablished` after port remap

**Error:**
```
ActiveRecord::ConnectionNotEstablished: connection to server at "172.18.0.2",
port 5433 failed: Connection refused
```

**Root cause:** `config/database.yml` reads `DB_PORT` and defaults to `5433`
when the env var is not set. The `web` and `worker` containers never had
`DB_PORT` defined, so Rails tried to connect on port `5433` — the host port —
which does not exist inside Docker's network. The `db` container only listens
on `5432` internally.

**Fix:** Add `DB_PORT: 5432` to both `web` and `worker` environment blocks in
`docker-compose.yml` (already applied above), then recreate the containers.

---

## Confirming Docker DB Is Healthy Before Connecting

```bash
# Should show db as Up with port mapping
docker compose ps db

# Verify credentials from inside the container
docker compose exec db psql -U postgres -d nexus_development -c "\l"
```

---

## Troubleshooting

### Connection timeout (not refused)

You are connecting to a Docker internal IP (`172.18.0.2`) from Windows.
That IP is not routable outside WSL2. Use Option B or C instead.

### `Connection refused` on the container IP after a restart

The container received a new IP. Re-run:

```bash
docker inspect practice-nexus-db-1 \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Update the DBeaver host field with the new IP, or switch to Option B/C to
avoid this entirely.

### Auth error persists after stopping local Postgres

The local Postgres volume may have initialized the `postgres` user with a
different password. Check from inside the Docker container:

```bash
docker compose exec db psql -U postgres -c "\du"
```

If that also fails, the Docker volume was initialized with different
credentials. Wipe and reinitialize:

```bash
docker compose down -v          # destroys the postgres_data volume
docker compose up -d db
docker compose exec db psql -U postgres -c "\l"
```

Then re-run migrations:

```bash
docker compose run --rm web bundle exec rails db:migrate
```
