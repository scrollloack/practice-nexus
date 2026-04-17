# 14 — README Update

## Concept: What This Battle Plan Covers

The root `README.md` is the entry point for anyone opening this repo. Right now it is
the default Rails-generated placeholder. This plan replaces it with a real project
README covering:

1. **Project overview** — what Nexus is and why it exists (from `01-project-overview-architecture.md`)
2. **Architecture** — the monorepo structure, engines, and request flow
3. **Prerequisites** — required tools and versions (from `02-prerequisites.md`)
4. **How to run** — full Docker-based startup sequence (from `04-docker-setup.md`)
5. **Service URLs** — where to access each running service
6. **Useful commands** — day-to-day Docker operations

---

## Planned README Structure

```
# Practice Nexus

## Overview
  - What Nexus is
  - The two engines and their Kafka roles

## Architecture
  - Monorepo directory tree
  - Request flow diagram

## Prerequisites
  - Required tools table (Ruby, Rails, Docker, Docker Compose, Bundler)

## Running the Project

  ### First-time setup
    - Clone, bundle, docker build, db:create, db:migrate

  ### Start all services
    - docker compose up -d
    - docker compose ps

  ### Service URLs
    - Rails app      → http://localhost:3000
    - GraphiQL UI    → http://localhost:3000/graphiql
    - Kafdrop UI     → http://localhost:9000

## Useful Docker Commands
  - Logs, stop, wipe, rebuild
```

---

## Files Touched

| File | Action |
|------|--------|
| `README.md` | Full rewrite — replaces default Rails placeholder |

No other files are changed.

---

## Awaiting Approval

Review the planned structure above. Reply to proceed with the rewrite.
