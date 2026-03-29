# 03 — Project Setup

## Concept: What Is a Rails Application?

A Rails application follows the MVC (Model-View-Controller) pattern. When we pass `--api`,
we strip out view-layer middleware (cookies, sessions, HTML rendering) since we only want
JSON responses and a GraphQL endpoint.

## Create the Rails App

```bash
# Create the app (API mode, PostgreSQL)
rails new nexus --api --database=postgresql

# Navigate into it
cd nexus
```

## Initial Directory Review

```
nexus/
├── app/
│   ├── controllers/    ← HTTP request handlers
│   ├── models/         ← ActiveRecord models
│   └── ...
├── config/
│   ├── database.yml    ← DB connection config
│   └── routes.rb       ← URL routing
├── db/
│   └── migrate/        ← DB migration files
├── Gemfile             ← Ruby dependency declarations
└── ...
```

## Update `config/database.yml`

We'll use environment variables so Docker can inject credentials:

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  port: <%= ENV.fetch("DB_PORT", 5432) %>
  username: <%= ENV.fetch("DB_USERNAME", "postgres") %>
  password: <%= ENV.fetch("DB_PASSWORD", "password") %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default
  database: nexus_development

test:
  <<: *default
  database: nexus_test

production:
  <<: *default
  database: nexus_production
```
