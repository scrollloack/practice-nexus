# Battle Plan: Rails Engine, Pub/Sub, Kafka & GraphQL

> **AI Context:** This is a guided learning project called **Nexus** — a Rails monorepo that
> teaches Rails Engines, GraphQL, and Kafka Pub/Sub through building a user + email notification
> system. Each section builds on the previous one. Code blocks are complete and runnable.
> Concept explanations precede each implementation step.

---

## Table of Contents

1. [Project Overview & Architecture](#1-project-overview--architecture)
2. [Prerequisites](#2-prerequisites)
3. [Project Setup](#3-project-setup)
4. [Docker Setup](#4-docker-setup)
5. [Gem Reference](#5-gem-reference)
6. [Rails Engine Creation](#6-rails-engine-creation)
7. [GraphQL Fundamentals](#7-graphql-fundamentals)
8. [Kafka Fundamentals](#8-kafka-fundamentals)
9. [Wiring It Together](#9-wiring-it-together)
10. [Testing the APIs (GraphiQL + Kafdrop)](#10-testing-the-apis-graphiql--kafdrop)

---

## 1. Project Overview & Architecture

### What We're Building

**Nexus** is a monorepo Rails application with two mountable Rails Engines:

| Engine | Responsibility | Kafka Role |
|--------|---------------|------------|
| `UserEngine` | Create & query users | **Producer** — publishes `user.created` events |
| `EmailEngine` | Send welcome emails | **Consumer** — listens to `user.created` events and sends email via ActionMailer |

### Why This Example?

- User registration triggering a welcome email is a universally understood pattern
- It creates a natural Kafka producer/consumer story with a real-world side effect (email)
- CRUD operations map cleanly to GraphQL mutations and queries
- Simple enough to finish in a day; deep enough to understand all the concepts

### Architecture Diagram

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

> **Note on Monorepo + Docker:** Both engines share one PostgreSQL instance but use
> separate table namespaces (`user_engine_users`, `email_engine_processed_events`). In production
> microservices you would have separate databases per service. This monorepo approach
> lets you learn all the concepts without the overhead of managing multiple repos.

---

## 2. Prerequisites

### Required Tools

| Tool | Version | Check Command |
|------|---------|---------------|
| Ruby | >= 3.2 | `ruby -v` |
| Rails | >= 7.1 | `rails -v` |
| Docker | >= 24 | `docker -v` |
| Docker Compose | >= 2.20 | `docker compose version` |
| Bundler | >= 2.4 | `bundler -v` |

### Install Ruby (via rbenv — recommended)

```bash
# Install rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Add to shell profile (~/.bashrc or ~/.zshrc)
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install Ruby 3.3
rbenv install 3.3.0
rbenv global 3.3.0

# Verify
ruby -v  # => ruby 3.3.0
```

### Install Rails

```bash
gem install rails -v '~> 7.1'
rails -v  # => Rails 7.1.x
```

### Install Docker

Follow the official docs for your OS: https://docs.docker.com/engine/install/

Verify:
```bash
docker -v
docker compose version
```

---

## 3. Project Setup

### Concept: What Is a Rails Application?

A Rails application follows the MVC (Model-View-Controller) pattern. When we pass `--api`,
we strip out view-layer middleware (cookies, sessions, HTML rendering) since we only want
JSON responses and a GraphQL endpoint.

### Create the Rails App

```bash
# Create the app (API mode, PostgreSQL)
rails new nexus --api --database=postgresql

# Navigate into it
cd nexus
```

### Initial Directory Review

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

### Update `config/database.yml`

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

---

## 4. Docker Setup

### Concept: Why Docker?

Docker lets you run Kafka, PostgreSQL, and Zookeeper locally without installing them
natively. `docker-compose.yml` defines all services in one file so you can spin up
the entire stack with one command.

### Services We Need

| Service | Purpose | Port |
|---------|---------|------|
| `db` | PostgreSQL database | 5432 |
| `zookeeper` | Required by Kafka for cluster coordination | 2181 |
| `kafka` | Message broker — handles topics, producers, consumers | 9092 |
| `kafdrop` | Web UI to inspect Kafka topics and messages | 9000 |
| `web` | Rails application | 3000 |

### Create `Dockerfile`

```dockerfile
# Dockerfile
FROM ruby:3.3-slim

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  git \
  curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy app
COPY . .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Create `docker-compose.yml`

```yaml
# docker-compose.yml
version: "3.9"

services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: nexus_development
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  zookeeper:
    image: bitnami/zookeeper:latest
    environment:
      ALLOW_ANONYMOUS_LOGIN: "yes"
    ports:
      - "2181:2181"

  kafka:
    image: bitnami/kafka:latest
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_CFG_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092
      KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"
      ALLOW_PLAINTEXT_LISTENER: "yes"

  kafdrop:
    image: obsidiandynamics/kafdrop:latest
    depends_on:
      - kafka
    ports:
      - "9000:9000"
    environment:
      KAFKA_BROKERCONNECT: kafka:9092
      JVM_OPTS: "-Xms32M -Xmx64M"

  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    volumes:
      - .:/app
    ports:
      - "3000:3000"
    depends_on:
      - db
      - kafka
    environment:
      DB_HOST: db
      DB_USERNAME: postgres
      DB_PASSWORD: password
      RAILS_ENV: development
      KAFKA_BROKER: kafka:9092

volumes:
  postgres_data:
```

### Start the Infrastructure

```bash
# Start everything in detached mode (background)
docker compose up -d

# Verify all services are running
docker compose ps

# Check Kafdrop is accessible
open http://localhost:9000

# Check Rails is accessible
open http://localhost:3000
```

> **Gotcha:** On first run, Kafka takes ~10-15 seconds to be ready. If Rails fails to
> connect on startup, run `docker compose restart web` after a few seconds.

### Useful Docker Commands

```bash
# View logs for a specific service
docker compose logs -f kafka
docker compose logs -f web

# Stop all services
docker compose down

# Stop and remove volumes (wipe DB data)
docker compose down -v

# Rebuild the Rails image after Gemfile changes
docker compose build web
docker compose up -d web
```

---

## 5. Gem Reference

> This is a reference for the important gems used in this project.
> Not every gem is listed — only those directly related to the learning goals.

### Add to `Gemfile`

```ruby
# Gemfile

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.0"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"           # PostgreSQL adapter for ActiveRecord
gem "puma", "~> 6.0"         # Web server

# GraphQL
gem "graphql", "~> 2.3"      # Core GraphQL-Ruby library
gem "graphiql-rails"         # Browser-based GraphQL IDE (development only)

# Kafka / Pub-Sub
gem "karafka", "~> 2.3"      # Kafka client — producers + consumers (Rails-native)

group :development, :test do
  gem "debug"
end
```

```bash
bundle install
```

### Gem Roles Explained

| Gem | Role | Used In |
|-----|------|---------|
| `rails` | Framework — routing, ActiveRecord, middleware | Everywhere |
| `pg` | PostgreSQL database adapter. Translates ActiveRecord calls to SQL | All engines |
| `puma` | Multi-threaded web server. Handles concurrent HTTP requests | Main app |
| `graphql` | Defines GraphQL schema, types, mutations, queries, and resolvers | Main app + engines |
| `graphiql-rails` | Mounts an interactive browser UI at `/graphiql` to test queries | Main app (dev only) |
| `karafka` | Kafka client framework for Ruby/Rails. Manages producers and consumers with a Rails-like DSL | UserEngine (producer), EmailEngine (consumer) |

---

## 6. Rails Engine Creation

### Concept: What Is a Rails Engine?

A **Rails Engine** is a miniature Rails application that can be mounted inside a parent
Rails app. Think of it like a Ruby gem that ships its own models, controllers, routes,
and migrations. Engines are how large Rails apps achieve modularity.

**Key differences from a regular Rails app:**

| Regular Rails App | Rails Engine |
|------------------|-------------|
| Standalone — runs on its own | Mounted inside a parent app |
| Has `config/routes.rb` as root | Its routes are namespaced and mounted |
| Models are in global namespace | Models are namespaced (e.g., `UserEngine::User`) |
| Manages its own DB | Shares parent app's DB connection |

**`--mountable` flag** — generates a fully isolated engine with its own namespace,
routes, and controllers. This is what we use for service-like engines.

### Create the Engines Directory

```bash
# From the nexus/ root
mkdir -p engines
```

### Generate `UserEngine`

```bash
# Generate a mountable engine inside engines/
rails plugin new engines/user_engine --mountable --database=postgresql --skip-test
```

This creates:
```
engines/user_engine/
├── app/
│   ├── controllers/user_engine/
│   │   └── application_controller.rb
│   └── models/user_engine/
├── config/
│   └── routes.rb              ← Engine's own routes (namespaced)
├── db/
│   └── migrate/               ← Engine's migrations
├── lib/
│   ├── user_engine.rb         ← Engine class definition
│   └── user_engine/
│       └── engine.rb          ← Rails::Engine subclass
└── user_engine.gemspec        ← Treat it like a gem
```

### Generate `EmailEngine`

```bash
rails plugin new engines/email_engine --mountable --database=postgresql --skip-test
```

### Reference Engines from Main App's `Gemfile`

Engines are referenced as local gems using `path:`:

```ruby
# Gemfile (in nexus/ root)
gem "user_engine", path: "engines/user_engine"
gem "email_engine", path: "engines/email_engine"
```

```bash
bundle install
```

### Mount Engines in `config/routes.rb`

`EmailEngine` is a pure Kafka consumer — it has no HTTP endpoints, so we do not mount it.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount UserEngine::Engine => "/users"

  # GraphQL endpoint (added later)
  post "/graphql", to: "graphql#execute"

  # GraphiQL browser IDE (development only)
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
end
```

### Create the User Model

```bash
# Generate migration inside UserEngine
cd engines/user_engine
rails generate model User name:string email:string:uniq --no-test-framework
cd ../..

# Run all migrations from the root
rails db:migrate
```

The generated migration:
```ruby
# engines/user_engine/db/migrate/XXXXXX_create_user_engine_users.rb
class CreateUserEngineUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :user_engine_users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
    end
    add_index :user_engine_users, :email, unique: true
  end
end
```

The model:
```ruby
# engines/user_engine/app/models/user_engine/user.rb
module UserEngine
  class User < ApplicationRecord
    validates :name, presence: true
    validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  end
end
```

> **Why `UserEngine::User` and not just `User`?**
> Namespacing prevents collisions. If the main app or another engine also defines a
> `User` model, they won't interfere. This is the "isolated" part of a mountable engine.

### Create the Mailer (EmailEngine)

`EmailEngine` uses Rails' built-in **ActionMailer** — no extra gem required.

```ruby
# engines/email_engine/app/mailers/email_engine/user_mailer.rb
module EmailEngine
  class UserMailer < ActionMailer::Base
    default from: "noreply@nexus.app"

    def welcome(user_id:, name:, email:)
      @name  = name
      @email = email
      mail(to: email, subject: "Welcome to Nexus, #{name}!")
    end
  end
end
```

```erb
<%# engines/email_engine/app/views/email_engine/user_mailer/welcome.text.erb %>
Hi <%= @name %>,

Your account has been created successfully.
Email: <%= @email %>

Welcome aboard!
— The Nexus Team
```

Add to `config/environments/development.rb`:
```ruby
config.action_mailer.delivery_method  = :test
config.action_mailer.perform_deliveries = true
```

### Verify the Setup

```bash
# Open Rails console
rails console

# Create a user
user = UserEngine::User.create!(name: "Alice", email: "alice@example.com")
# => #<UserEngine::User id: 1, name: "Alice", email: "alice@example.com">

# Manually send a welcome email
EmailEngine::UserMailer.welcome(user_id: user.id, name: user.name, email: user.email).deliver_now

# Inspect sent emails (delivery_method: :test stores in memory)
ActionMailer::Base.deliveries.last
# => #<Mail::Message to: ["alice@example.com"], subject: "Welcome to Nexus, Alice!">
```

---

## 7. GraphQL Fundamentals

### Concept: GraphQL vs REST

Before writing code, understand the philosophical difference:

**REST API:**
```
GET  /users/1          → returns { id, name, email, created_at, updated_at }
GET  /users            → separate request for all users
POST /users            → creates a user
```

Problems:
- **Over-fetching** — you get fields you don't need
- **Under-fetching** — you need multiple requests to get related data
- **Multiple endpoints** — one endpoint per resource/action

**GraphQL API:**
```graphql
# Single request, you define exactly what you want
query {
  user(id: 1) {
    name
    email
  }
}
```

Benefits:
- **One endpoint** (`POST /graphql`) for everything
- **Declare your data shape** — get exactly what you ask for
- **Strongly typed schema** — self-documenting, introspectable

### GraphQL Building Blocks

| Concept | What it is | Rails Analogy |
|---------|-----------|---------------|
| **Type** | Shape of an object (what fields it has) | ActiveRecord model shape |
| **Query** | Read operation | `GET` request / `index`/`show` actions |
| **Mutation** | Write operation | `POST`/`PUT`/`DELETE` requests |
| **Resolver** | The method that fetches/writes data | Controller action body |
| **Input Type** | Structured input for mutations | Strong params / form object |
| **Schema** | Root definition — wires queries + mutations together | `routes.rb` |

### Initialize GraphQL in the Main App

```bash
# From nexus/ root
rails generate graphql:install
```

This creates:
```
app/graphql/
├── nexus_schema.rb          ← Root schema
├── mutations/
│   └── base_mutation.rb
└── types/
    ├── base_argument.rb
    ├── base_field.rb
    ├── base_input_object.rb
    ├── base_mutation.rb
    ├── base_object.rb
    ├── mutation_type.rb     ← All mutations plugged in here
    └── query_type.rb        ← All queries plugged in here
```

And updates `app/controllers/graphql_controller.rb` to handle POST `/graphql`.

### Step 7.1 — Define a GraphQL Type

A **Type** maps an ActiveRecord model to a GraphQL object. It declares which fields
are exposed and what their types are.

```ruby
# engines/user_engine/app/graphql/user_engine/types/user_type.rb
module UserEngine
  module Types
    class UserType < GraphQL::Schema::Object
      description "A registered user in the system"

      # Each field corresponds to an attribute on UserEngine::User
      field :id,         Integer, null: false
      field :name,       String,  null: false
      field :email,      String,  null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
```

> **How it connects to ActiveRecord:**
> When GraphQL resolves a `UserType`, it receives a `UserEngine::User` instance.
> Each `field :name` call tells GraphQL to call `.name` on that instance.
> This is automatic — no extra code needed because field names match method names.

### Step 7.2 — Define a Query (Read Operation)

A **Query** is how clients read data. Define query fields in `query_type.rb`.

```ruby
# engines/user_engine/app/graphql/user_engine/resolvers/users_resolver.rb
module UserEngine
  module Resolvers
    class UsersResolver < GraphQL::Schema::Resolver
      description "Fetch all users"
      type [Types::UserType], null: false

      def resolve
        UserEngine::User.all
      end
    end
  end
end
```

```ruby
# engines/user_engine/app/graphql/user_engine/resolvers/user_resolver.rb
module UserEngine
  module Resolvers
    class UserResolver < GraphQL::Schema::Resolver
      description "Fetch a single user by ID"
      type Types::UserType, null: true

      argument :id, Integer, required: true

      def resolve(id:)
        UserEngine::User.find_by(id: id)
      end
    end
  end
end
```

Wire these into the main app's `QueryType`:

```ruby
# app/graphql/types/query_type.rb
module Types
  class QueryType < Types::BaseObject
    # Delegate to UserEngine resolvers
    field :users, resolver: UserEngine::Resolvers::UsersResolver
    field :user,  resolver: UserEngine::Resolvers::UserResolver
  end
end
```

> **Why no EmailEngine resolvers?** `EmailEngine` is a pure event consumer — it has
> no data for clients to query, so it contributes nothing to the GraphQL schema.

**GraphQL query in GraphiQL (what you'd type in the browser):**
```graphql
query {
  users {
    id
    name
    email
  }
}

query {
  user(id: 1) {
    name
    email
    createdAt
  }
}
```

> **Notice:** `created_at` in Ruby becomes `createdAt` in GraphQL — the gem
> automatically camelCases field names.

### Step 7.3 — Define an Input Type

An **Input Type** defines the shape of data passed INTO a mutation.
It's like strong params in Rails — it validates and describes what the client sends.

```ruby
# engines/user_engine/app/graphql/user_engine/types/create_user_input.rb
module UserEngine
  module Types
    class CreateUserInput < GraphQL::Schema::InputObject
      description "Input fields required to create a new user"

      argument :name,  String, required: true,  description: "Full name of the user"
      argument :email, String, required: true,  description: "Unique email address"
    end
  end
end
```

### Step 7.4 — Define a Mutation (Write Operation)

A **Mutation** handles writes (create, update, delete). It takes an input type,
performs the operation, and returns the result.

```ruby
# engines/user_engine/app/graphql/user_engine/mutations/create_user.rb
module UserEngine
  module Mutations
    class CreateUser < GraphQL::Schema::Mutation
      description "Create a new user"

      # What goes IN  (the input type we defined above)
      argument :input, Types::CreateUserInput, required: true

      # What comes OUT (the type that will be returned)
      field :user,   Types::UserType, null: true
      field :errors, [String],        null: false

      def resolve(input:)
        user = UserEngine::User.new(
          name:  input[:name],
          email: input[:email]
        )

        if user.save
          # After successful save → publish Kafka event (covered in Section 8)
          UserEngine::Events::UserCreatedProducer.call(user)

          { user: user, errors: [] }
        else
          { user: nil, errors: user.errors.full_messages }
        end
      end
    end
  end
end
```

Wire into the main app's `MutationType`:

```ruby
# app/graphql/types/mutation_type.rb
module Types
  class MutationType < Types::BaseObject
    field :create_user, mutation: UserEngine::Mutations::CreateUser
  end
end
```

**GraphQL mutation in GraphiQL:**
```graphql
mutation {
  createUser(input: { name: "Alice", email: "alice@example.com" }) {
    user {
      id
      name
      email
    }
    errors
  }
}
```

> **Mutation vs Query — when to use which:**
> - Use **Query** for anything that reads data (no side effects)
> - Use **Mutation** for anything that changes data (creates, updates, deletes)
> This is a convention in GraphQL — technically both are just HTTP POSTs.

### Step 7.5 — Wire the Schema Together

```ruby
# app/graphql/nexus_schema.rb
class NexusSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # Enable lazy loading for N+1 prevention (optional but good practice)
  use GraphQL::Dataloader
end
```

### Summary: How GraphQL Maps to ActiveRecord

```
GraphQL Concept        →    Rails/ActiveRecord Equivalent
─────────────────────────────────────────────────────────
Schema                 →    routes.rb (the root entry point)
QueryType field        →    GET route + controller#index or #show
MutationType field     →    POST/PUT/DELETE route + controller action
Type (ObjectType)      →    ActiveRecord model shape (which columns are exposed)
Resolver#resolve       →    Controller action body (the actual logic)
Input Type argument    →    Strong params / permitted attributes
field :name, String    →    user.name (calls the method on the AR instance)
```

---

## 8. Kafka Fundamentals

### Concept: What Is Kafka?

**Apache Kafka** is a distributed event streaming platform. It acts as a persistent,
ordered log of events that multiple services can read from independently.

Think of it like a post office:
- A **Producer** drops a letter (event) into a **mailbox** (topic)
- Any number of **Consumers** can pick up letters from that mailbox
- Letters stay in the mailbox for a configurable period — consumers can re-read them

### Core Kafka Vocabulary

| Term | Definition | Our Example |
|------|-----------|-------------|
| **Topic** | A named channel/category of events | `user.created` |
| **Producer** | Code that publishes events to a topic | `UserEngine` after saving a user |
| **Consumer** | Code that subscribes to a topic and processes events | `EmailEngine` listening for new users and sending welcome emails |
| **Message/Event** | The payload sent through Kafka (usually JSON) | `{ "user_id": 1, "email": "alice@example.com" }` |
| **Offset** | The position of a message in a topic (like a line number) | Used for idempotency |
| **Consumer Group** | A group of consumers sharing the workload of a topic | All EmailEngine instances share one group |
| **Partition** | A topic can be split into partitions for parallelism | We use 1 partition for simplicity |

### Why Kafka for Pub/Sub?

```
Without Kafka (tight coupling):
  UserEngine → directly calls EmailEngine HTTP API
  Problem: EmailEngine must be running; failure cascades

With Kafka (loose coupling):
  UserEngine → publishes event → Kafka topic
                                      ↓
                              EmailEngine consumer → sends welcome email
  Benefit: EmailEngine can be down; messages queue up and process when it restarts
```

### Configure Karafka

```bash
# From nexus/ root
bundle exec karafka install
```

This creates `karafka.rb` at the root. Replace its contents:

```ruby
# karafka.rb
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BROKER", "localhost:9092")
    }
    config.client_id = "nexus"
    config.consumer_persistence = true
  end

  routes.draw do
    # EmailEngine subscribes to the user.created topic
    topic "user.created" do
      consumer EmailEngine::Consumers::UserCreatedConsumer
    end
  end
end
```

### Step 8.1 — Define the Topic

Topics in Kafka are auto-created when a producer first publishes to them
(we enabled `KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"` in docker-compose).

Our topic name: **`user.created`**

Convention: Use dot-notation `<service>.<event>` — it's readable and groups related
events visually in Kafdrop.

### Step 8.2 — Create a Kafka Producer (UserEngine)

A **Producer** publishes an event message to a topic after a business action completes.

```ruby
# engines/user_engine/app/events/user_engine/events/user_created_producer.rb
module UserEngine
  module Events
    class UserCreatedProducer
      TOPIC = "user.created".freeze

      # .call(user) is the single entry point
      def self.call(user)
        message = {
          event:      "user.created",
          user_id:    user.id,
          name:       user.name,
          email:      user.email,
          occurred_at: user.created_at.iso8601
        }.to_json

        Karafka.producer.produce_sync(
          topic:   TOPIC,
          payload: message,
          key:     user.id.to_s   # ← message key (important for idempotency — see Step 8.5)
        )
      end
    end
  end
end
```

> **What is `produce_sync`?**
> It publishes the message and waits for Kafka to acknowledge receipt before returning.
> Use `produce_async` for fire-and-forget (higher throughput, less guarantee).
> For learning, `produce_sync` is clearer.

### Step 8.3 — Create a Kafka Consumer (EmailEngine)

A **Consumer** subscribes to a topic and processes each message as it arrives.
Karafka runs consumers as background threads (separate from the Rails web server).

```ruby
# engines/email_engine/app/consumers/email_engine/consumers/user_created_consumer.rb
module EmailEngine
  module Consumers
    class UserCreatedConsumer < Karafka::BaseConsumer
      def consume
        # `messages` is a batch of events — Karafka delivers them in batches
        messages.each do |message|
          process_event(message)
        end
      end

      private

      def process_event(message)
        payload = JSON.parse(message.payload, symbolize_names: true)

        Rails.logger.info "[EmailEngine] Received user.created for user_id=#{payload[:user_id]}"

        # Idempotency check — don't send duplicate welcome emails (see Step 8.5)
        return if ProcessedEvent.exists?(event_id: message.offset, topic: message.topic)

        # Business logic: send a welcome email to the newly created user
        EmailEngine::UserMailer.welcome(
          user_id: payload[:user_id],
          name:    payload[:name],
          email:   payload[:email]
        ).deliver_now

        # Record that we've processed this event
        ProcessedEvent.create!(
          event_id:    message.offset,
          topic:       message.topic,
          processed_at: Time.current
        )
      end
    end
  end
end
```

### Step 8.4 — Start the Karafka Consumer Worker

The web server (`rails server`) handles HTTP. Karafka consumers run separately:

```bash
# In a second terminal (or add as a second Docker service)
bundle exec karafka server
```

In Docker, add a `worker` service to `docker-compose.yml`:

```yaml
  worker:
    build: .
    command: bundle exec karafka server
    volumes:
      - .:/app
    depends_on:
      - kafka
      - db
    environment:
      DB_HOST: db
      DB_USERNAME: postgres
      DB_PASSWORD: password
      RAILS_ENV: development
      KAFKA_BROKER: kafka:9092
```

### Step 8.5 — Event Idempotency

#### What Is Idempotency?

An operation is **idempotent** if running it multiple times produces the same result
as running it once.

**Why does this matter in Kafka?**

Kafka guarantees "at-least-once" delivery by default. This means:
- Under network failures or consumer crashes, **the same message may be delivered more than once**
- Without idempotency protection, you'd create duplicate records

```
Timeline without idempotency protection:
  Message delivered → welcome email sent → consumer crashes before committing offset
  Message re-delivered → welcome email sent AGAIN → duplicate email!

Timeline with idempotency protection:
  Message delivered → idempotency check → email sent → offset committed
  Message re-delivered → idempotency check → already processed → SKIP → safe!
```

#### Idempotency Strategies

**Strategy 1 — Database deduplication (what we use above):**
```ruby
# Store processed event offsets in a DB table
return if ProcessedEvent.exists?(event_id: message.offset, topic: message.topic)
```

**Strategy 2 — Idempotent email delivery:**
```ruby
# The ProcessedEvent guard already prevents re-delivery.
# As a belt-and-suspenders check you could also query for prior deliveries,
# but the offset-based guard in Strategy 1 is sufficient for our case.
```

**Strategy 3 — Message key-based ordering:**
```ruby
# Producer: set key: user.id.to_s
# Kafka routes all messages with the same key to the same partition
# → events for the same user are always processed in order
Karafka.producer.produce_sync(topic: TOPIC, payload: message, key: user.id.to_s)
```

> **Rule of thumb:** Always design your Kafka consumers to be idempotent.
> Assume any message _can_ arrive more than once. Make re-processing safe.

#### Migration for `ProcessedEvent`

`EmailEngine` only needs a `ProcessedEvent` table — there is no data to persist beyond
tracking which events have already triggered an email (idempotency guard).

```ruby
# engines/email_engine/db/migrate/XXXXXX_create_email_engine_processed_events.rb
class CreateEmailEngineProcessedEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :email_engine_processed_events do |t|
      t.string   :event_id,     null: false
      t.string   :topic,        null: false
      t.datetime :processed_at, null: false
      t.timestamps
    end
    add_index :email_engine_processed_events, [:event_id, :topic], unique: true
  end
end
```

```ruby
# engines/email_engine/app/models/email_engine/processed_event.rb
module EmailEngine
  class ProcessedEvent < ApplicationRecord
  end
end
```

```bash
rails db:migrate
```

### Kafka Mental Model Summary

```
UserEngine::User.save!
        │
        ▼
UserCreatedProducer.call(user)
        │  publishes JSON to topic "user.created"
        ▼
┌───────────────────────────────┐
│  Kafka Topic: "user.created"  │
│  [offset 0] [offset 1] ...    │  ← Messages are persisted here
└───────────────────────────────┘
        │  Karafka consumer reads from offset
        ▼
UserCreatedConsumer#consume       (inside EmailEngine)
        │  idempotency check      → skip if ProcessedEvent exists
        │  UserMailer.welcome     → sends welcome email via ActionMailer
        │  ProcessedEvent.create! → records offset to prevent re-processing
        ▼
    Done ✓
```

---

## 9. Wiring It Together

### Concept: The Full Picture

At this point you have:
- Two Rails Engines (`UserEngine`, `EmailEngine`) — `UserEngine` with a model and GraphQL types, `EmailEngine` with a Kafka consumer and ActionMailer mailer
- A Kafka producer in `UserEngine` and a consumer in `EmailEngine`
- A Docker stack running PostgreSQL + Kafka + Kafdrop

This section connects all the pieces so the full flow works end-to-end.

### Final File Structure Checklist

```
nexus/
├── Dockerfile
├── Gemfile                                        ✓ all gems + engine paths
├── Gemfile.lock
├── docker-compose.yml                             ✓ db + zookeeper + kafka + kafdrop + web + worker
├── karafka.rb                                     ✓ routes user.created → UserCreatedConsumer
├── app/
│   ├── controllers/
│   │   └── graphql_controller.rb                  ✓ auto-generated by graphql:install
│   └── graphql/
│       ├── nexus_schema.rb                        ✓ mutation + query types wired
│       └── types/
│           ├── query_type.rb                      ✓ user resolver fields only
│           └── mutation_type.rb                   ✓ create_user field only
├── config/
│   ├── database.yml                               ✓ uses ENV vars
│   └── routes.rb                                  ✓ mounts UserEngine + graphql + graphiql
└── engines/
    ├── user_engine/
    │   └── app/
    │       ├── events/user_engine/events/
    │       │   └── user_created_producer.rb       ✓ publishes to user.created
    │       ├── graphql/user_engine/
    │       │   ├── types/user_type.rb             ✓
    │       │   ├── types/create_user_input.rb     ✓
    │       │   ├── mutations/create_user.rb       ✓ calls producer after save
    │       │   └── resolvers/                     ✓ users_resolver + user_resolver
    │       └── models/user_engine/user.rb         ✓
    └── email_engine/
        └── app/
            ├── consumers/email_engine/consumers/
            │   └── user_created_consumer.rb       ✓ idempotent, sends welcome email
            ├── mailers/email_engine/
            │   └── user_mailer.rb                 ✓ ActionMailer — welcome email
            ├── views/email_engine/user_mailer/
            │   ├── welcome.html.erb               ✓
            │   └── welcome.text.erb               ✓
            └── models/email_engine/
                └── processed_event.rb             ✓
```

### Engine Autoload Paths

Rails engines need to tell the parent app where to find their files.
Update each engine's `engine.rb`:

```ruby
# engines/user_engine/lib/user_engine/engine.rb
module UserEngine
  class Engine < ::Rails::Engine
    isolate_namespace UserEngine

    # Tell Rails to autoload engine's graphql + events directories
    config.autoload_paths += %W[
      #{root}/app/graphql
      #{root}/app/events
    ]
  end
end
```

```ruby
# engines/email_engine/lib/email_engine/engine.rb
module EmailEngine
  class Engine < ::Rails::Engine
    isolate_namespace EmailEngine

    config.autoload_paths += %W[
      #{root}/app/consumers
      #{root}/app/mailers
    ]
  end
end
```

### GraphiQL Setup

`graphiql-rails` requires the asset pipeline. Since we used `--api`, add Sprockets:

```ruby
# Gemfile
gem "sprockets-rails"
```

```ruby
# config/application.rb
require "sprockets/railtie"  # add this line
```

Create the assets initializer:

```ruby
# config/initializers/assets.rb
Rails.application.config.assets.precompile += %w[graphiql/rails/application.js graphiql/rails/application.css]
```

Routes are already set (from Section 3):

```ruby
if Rails.env.development?
  mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
end
```

GraphiQL will be available at: **http://localhost:3000/graphiql**

### Run the Full Stack

```bash
# 1. Build and start all services
docker compose up --build -d

# 2. Create and migrate the database
docker compose exec web rails db:create db:migrate

# 3. Verify the web server is up
curl http://localhost:3000/graphql -X POST \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __typename }"}'
# Expected: {"data":{"__typename":"Query"}}

# 4. Verify Karafka worker is running
docker compose logs worker
# Expected: Karafka server started, listening on user.created
```

### Verify the Event Flow Manually

```bash
# Open a Rails console to directly test the producer
docker compose exec web rails console

# Publish a test event
user = UserEngine::User.create!(name: "Test", email: "test@example.com")
UserEngine::Events::UserCreatedProducer.call(user)
# => message produced to topic user.created

# Open Kafdrop to see the message:
# http://localhost:9000 → Topics → user.created → View Messages

# Check the consumer processed it and sent the email
EmailEngine::ProcessedEvent.last
# => #<EmailEngine::ProcessedEvent event_id: "0", topic: "user.created">

# Inspect the sent email (delivery_method: :test stores emails in memory)
ActionMailer::Base.deliveries.last
# => #<Mail::Message to: ["test@example.com"], subject: "Welcome to Nexus, Test!">
```

---

## 10. Testing the APIs (GraphiQL + Kafdrop)

### Concept: What Are We Testing?

This section is a guided walkthrough — you run each step in order and verify the
expected output. By the end you will have exercised every layer of the stack:

```
GraphiQL (browser) → GraphQL mutation → ActiveRecord → Kafka producer
                                                              ↓
                                                      Kafka topic
                                                              ↓
                                               Karafka consumer → ActionMailer (welcome email)
```

---

### Step 10.1 — Open GraphiQL

1. Make sure all Docker services are running: `docker compose ps`
2. Open your browser: **http://localhost:3000/graphiql**
3. You should see the GraphiQL IDE with a left panel (query editor) and right panel (results)

> **Tip:** Click the **Docs** button (top right) to explore the auto-generated schema
> documentation. This is introspection — one of GraphQL's superpowers.

---

### Step 10.2 — Introspect the Schema

Paste this into GraphiQL and run it (▶ button):

```graphql
query IntrospectSchema {
  __schema {
    queryType  { name }
    mutationType { name }
    types {
      name
      kind
    }
  }
}
```

**Expected:** A list of all types including `UserType`, `CreateUserInput`, etc.

**What you're learning:** GraphQL schemas are self-describing. This is how tools like
GraphiQL auto-complete your queries — they query the schema itself.

---

### Step 10.3 — Create a User (Mutation)

```graphql
mutation CreateUser {
  createUser(input: { name: "Alice", email: "alice@example.com" }) {
    user {
      id
      name
      email
      createdAt
    }
    errors
  }
}
```

**Expected response:**
```json
{
  "data": {
    "createUser": {
      "user": {
        "id": 1,
        "name": "Alice",
        "email": "alice@example.com",
        "createdAt": "2026-03-28T00:00:00Z"
      },
      "errors": []
    }
  }
}
```

**What happened behind the scenes:**
1. Rails received `POST /graphql` with the mutation payload
2. `CreateUser#resolve` ran — called `UserEngine::User.create!`
3. `UserCreatedProducer.call(user)` published a message to Kafka topic `user.created`
4. The Karafka worker consumed the event and `EmailEngine::UserMailer.welcome` sent a welcome email to Alice

---

### Step 10.4 — Verify the Kafka Event in Kafdrop

1. Open **http://localhost:9000**
2. Click **Topics** in the left sidebar
3. Click **user.created**
4. Click **View Messages** → you should see the JSON payload:

```json
{
  "event": "user.created",
  "user_id": 1,
  "name": "Alice",
  "email": "alice@example.com",
  "occurred_at": "2026-03-28T00:00:00Z"
}
```

**What you're learning:**
- The **topic** is the named channel (`user.created`)
- The **message** is the JSON payload
- The **offset** (shown as a number) is the position of this message in the topic log
- Kafdrop lets you see messages without writing any consumer code

---

### Step 10.5 — Verify the Consumer Sent the Email

In a terminal:

```bash
docker compose exec web rails console

# Was the email delivered?
ActionMailer::Base.deliveries.count
# => 1

ActionMailer::Base.deliveries.last.to
# => ["alice@example.com"]

ActionMailer::Base.deliveries.last.subject
# => "Welcome to Nexus, Alice!"

# Was the event recorded to prevent re-processing?
EmailEngine::ProcessedEvent.all
# => [#<EmailEngine::ProcessedEvent event_id: "0", topic: "user.created">]
```

---

### Step 10.6 — Query Users (Query)

Back in GraphiQL:

```graphql
query GetAllUsers {
  users {
    id
    name
    email
  }
}
```

**Expected:**
```json
{
  "data": {
    "users": [
      { "id": 1, "name": "Alice", "email": "alice@example.com" }
    ]
  }
}
```

```graphql
query GetOneUser {
  user(id: 1) {
    id
    name
    email
    createdAt
  }
}
```

---

### Step 10.7 — Test Validation Errors

Try creating a duplicate user — GraphQL returns errors gracefully instead of crashing:

```graphql
mutation DuplicateUser {
  createUser(input: { name: "Alice", email: "alice@example.com" }) {
    user {
      id
    }
    errors
  }
}
```

**Expected:**
```json
{
  "data": {
    "createUser": {
      "user": null,
      "errors": ["Email has already been taken"]
    }
  }
}
```

**What you're learning:** GraphQL mutations return errors as data (not HTTP 4xx codes).
The client always gets a `200 OK` — errors are in the `errors` field of the response body.

---

### Step 10.8 — Test Idempotency (Kafka Re-delivery Simulation)

```bash
docker compose exec web rails console

# Simulate re-delivery by manually calling the consumer twice
# with the same offset
message = OpenStruct.new(
  payload: { event: "user.created", user_id: 1, name: "Alice", email: "alice@example.com" }.to_json,
  offset:  "0",
  topic:   "user.created"
)

consumer = EmailEngine::Consumers::UserCreatedConsumer.new

# First delivery — should send the welcome email
consumer.send(:process_event, message)
ActionMailer::Base.deliveries.count  # => 1

# Second delivery — should be skipped (idempotency check)
consumer.send(:process_event, message)
ActionMailer::Base.deliveries.count  # => still 1 (no duplicate email!)
```

**What you're learning:** The `ProcessedEvent` guard prevents double-processing.
Re-running the same event is completely safe — Alice won't receive two welcome emails.

---

### What You've Learned — Final Summary

| Concept | Where You Used It |
|---------|------------------|
| **Rails Engine** | `UserEngine` and `EmailEngine` — isolated, mountable, namespaced |
| **Engine mounting** | `config/routes.rb` — `mount UserEngine::Engine => "/users"` (EmailEngine has no HTTP routes) |
| **GraphQL Type** | `UserType` — maps AR model fields to GraphQL |
| **GraphQL Query** | `users`, `user(id:)` — read operations |
| **GraphQL Mutation** | `createUser` — write operation that triggers the event chain |
| **Input Type** | `CreateUserInput` — typed, validated input |
| **Resolver** | `UsersResolver`, `UserResolver` — where the DB logic lives |
| **GraphQL vs REST** | One endpoint, declare your shape, no over/under-fetching |
| **Kafka Topic** | `user.created` — the named event channel |
| **Kafka Producer** | `UserCreatedProducer` — publishes JSON after user save |
| **Kafka Consumer** | `UserCreatedConsumer` (EmailEngine) — reacts to events asynchronously |
| **ActionMailer** | `UserMailer#welcome` — built-in Rails mailer, no extra gem needed |
| **Event Idempotency** | `ProcessedEvent` guard — prevents duplicate welcome emails on re-delivery |
| **Karafka** | Rails-native Kafka framework — producer API + consumer DSL |
| **Kafdrop** | Web UI to inspect topics, messages, and offsets |
| **Docker Compose** | Full stack in one command — DB + Kafka + Zookeeper + Rails |

---

> **Where to go next:**
> - Add GraphQL subscriptions (real-time updates via WebSockets)
> - Add authentication to GraphQL context (JWT in request headers)
> - Split engines into separate repos with their own databases (true microservices)
> - Add a dead-letter topic for failed consumer events
> - Explore Kafka Streams for stateful event processing
