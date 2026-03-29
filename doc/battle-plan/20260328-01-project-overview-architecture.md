# 01 — Project Overview & Architecture

## What We're Building

**Nexus** is a monorepo Rails application with two mountable Rails Engines:

| Engine | Responsibility | Kafka Role |
|--------|---------------|------------|
| `UserEngine` | Create & query users | **Producer** — publishes `user.created` events |
| `EmailEngine` | Send welcome emails | **Consumer** — listens to `user.created` events and sends email via ActionMailer |

## Why This Example?

- User registration triggering a welcome email is a universally understood pattern
- It creates a natural Kafka producer/consumer story with a real-world side effect (email)
- CRUD operations map cleanly to GraphQL mutations and queries
- Simple enough to finish in a day; deep enough to understand all the concepts

## Architecture Diagram

```
nexus/                          ← Monorepo root (one Git repo)
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
├── docker-compose.yml          ← Full infrastructure
├── Dockerfile
└── Gemfile                     ← All gems declared here
```

## Request Flow

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

> **Note on Monorepo + Docker:** Both engines share one PostgreSQL instance but use
> separate table namespaces (`user_engine_users`, `email_engine_processed_events`). In production
> microservices you would have separate databases per service. This monorepo approach
> lets you learn all the concepts without the overhead of managing multiple repos.
