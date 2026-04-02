# Practice Nexus

A monorepo Rails application demonstrating event-driven architecture using GraphQL,
Kafka, and mountable Rails Engines.

---

## Overview

**Nexus** is a Rails API application with two mountable Rails Engines that communicate
asynchronously via Kafka:

| Engine | Responsibility | Kafka Role |
|--------|---------------|------------|
| `UserEngine` | Create & query users | **Producer** — publishes `user.created` events |
| `EmailEngine` | Send welcome emails | **Consumer** — listens to `user.created` and sends email via ActionMailer |

User registration triggers a welcome email — a universally understood pattern that
creates a natural Kafka producer/consumer story with a real-world side effect.

---

## Architecture

### Monorepo Structure

```
nexus/
├── app/
│   └── graphql/                ← Unified GraphQL schema (mounts engine types)
│       ├── nexus_schema.rb
│       ├── mutations/
│       └── types/
├── engines/
│   ├── user_engine/            ← Rails Engine: User model + GraphQL + Kafka Producer
│   │   ├── app/
│   │   │   ├── models/user_engine/user.rb
│   │   │   ├── graphql/
│   │   │   └── events/         ← Kafka producers live here
│   │   └── db/migrate/
│   └── email_engine/           ← Rails Engine: ActionMailer + Kafka Consumer (no HTTP routes)
│       ├── app/
│       │   ├── mailers/email_engine/user_mailer.rb
│       │   ├── views/email_engine/user_mailer/
│       │   └── consumers/      ← Kafka consumers live here
│       └── db/migrate/
├── config/
│   └── routes.rb               ← Mounts UserEngine only (EmailEngine has no HTTP layer)
├── docker-compose.yml
├── Dockerfile
└── Gemfile
```

### Request Flow

```
Browser (GraphiQL)
    │
    ▼
Rails app (GraphQL endpoint: POST /graphql)
    │
    └─► UserEngine::Mutation::CreateUser
            │
            ├─► UserEngine::User.create! (ActiveRecord → PostgreSQL)
            │
            └─► Kafka Producer publishes to topic: "user.created"
                                │
                                ▼
                    EmailEngine::UserCreatedConsumer
                        (Kafka Consumer — runs as background worker)
                        Sends welcome email via ActionMailer
```

> Both engines share one PostgreSQL instance but use separate table namespaces
> (`user_engine_users`, `email_engine_processed_events`).

---

## Prerequisites

| Tool | Version | Check Command |
|------|---------|---------------|
| Ruby | >= 3.2 | `ruby -v` |
| Rails | >= 7.1 | `rails -v` |
| Docker | >= 24 | `docker -v` |
| Docker Compose | >= 2.20 | `docker compose version` |
| Bundler | >= 2.4 | `bundler -v` |

Install Docker via the official docs: https://docs.docker.com/engine/install/

---

## Running the Project

### First-time Setup

```bash
# Clone the repo
git clone git@github.com:ABandelaria/practice-nexus.git
cd practice-nexus

# Install gems
bundle install

# Build Docker images
docker compose build

# Start all services
docker compose up -d

# Create and migrate the database
docker compose exec web rails db:create db:migrate
```

### Start All Services

```bash
docker compose up -d

# Verify all containers are running
docker compose ps
```

### Docker Services

| Service | Purpose | Port |
|---------|---------|------|
| `db` | PostgreSQL database | 5432 |
| `zookeeper` | Kafka cluster coordination | 2181 |
| `kafka` | Message broker | 9092 |
| `kafdrop` | Kafka web UI | 9000 |
| `web` | Rails application | 3000 |
| `worker` | Karafka consumer worker | — |

### Service URLs

| Service | URL |
|---------|-----|
| Rails app | http://localhost:3000 |
| GraphiQL UI | http://localhost:3000/graphiql |
| Kafdrop UI | http://localhost:9000 |

> On first run, Kafka takes ~10-15 seconds to be ready. If Rails fails to connect,
> run `docker compose restart web` after a few seconds.

---

## Useful Docker Commands

```bash
# Follow logs for a service
docker compose logs -f web
docker compose logs -f worker
docker compose logs -f kafka

# Stop all services
docker compose down

# Stop and wipe all data (database volumes included)
docker compose down -v

# Rebuild the Rails image after Gemfile changes
docker compose build web
docker compose up -d web
```
