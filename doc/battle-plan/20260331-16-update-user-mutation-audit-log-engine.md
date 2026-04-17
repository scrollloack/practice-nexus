# 16 — updateUser Mutation + AuditEngine (Fan-out Pattern)

> **AI Context:** This document extends the Nexus practice project (Rails monorepo with engines,
> GraphQL, and Kafka). The existing system has: `UserEngine` (GraphQL queries + createUser mutation,
> Kafka producer), `EmailEngine` (Kafka consumer → welcome email). This document adds Feature 2:
> an `updateUser` GraphQL mutation that publishes a `user.updated` Kafka event, and a new
> `AuditEngine` that independently consumes **both** `user.created` and `user.updated` events,
> writing an immutable audit log. Key new patterns: partial update mutations, Kafka fan-out via
> consumer groups, and a consumer subscribing to multiple topics. Code blocks are complete and
> runnable. All new files follow the existing project conventions.

---

## Concept: What We're Building

This feature introduces three things in parallel:

1. **`updateUser` GraphQL mutation** — a partial update that accepts only the fields the client
   wants to change (name and/or email are both optional).

2. **`user.updated` Kafka topic** — a new event published after every successful user update,
   carrying what changed.

3. **`AuditEngine`** — a new mountable Rails Engine that acts as a pure Kafka consumer. It
   subscribes to *both* `user.created` and `user.updated` and writes every event into an
   immutable `audit_engine_audit_logs` table.

```
                           ┌──────────────────────────────────┐
                           │         Kafka Broker              │
                           │                                   │
 createUser mutation ──▶  topic: user.created  ──┬──▶ EmailEngine (welcome email)
                           │                      └──▶ AuditEngine (audit log: "created")
                           │                                   │
 updateUser mutation ──▶  topic: user.updated  ────▶ AuditEngine (audit log: "updated")
                           │                                   │
                           └──────────────────────────────────┘
```

---

## New Patterns This Feature Introduces

| Pattern | What it means | Where you'll see it |
|---------|--------------|---------------------|
| **Fan-out** | One topic → multiple independent consumers | `user.created` consumed by both EmailEngine AND AuditEngine |
| **Consumer Groups** | How Kafka isolates independent consumers of the same topic | `consumer_group :audit_service` in `karafka.rb` |
| **Multi-topic consumer** | One consumer class registered to multiple topics | `AuditEngine::Consumers::UserEventConsumer` on two topics |
| **Partial update mutation** | Optional arguments — only change what the client sends | `UpdateUserInput` with `required: false` fields |
| **Event-driven audit trail** | Reconstruct history from events, not polls | `audit_engine_audit_logs` table populated by Kafka events |

> **Why Consumer Groups for fan-out?**
> Kafka tracks each consumer group's read offset independently. If EmailEngine and AuditEngine
> share the same consumer group, Kafka would split messages between them (load balancing — each
> message goes to one consumer). With separate groups, both get every message independently.
> This is true fan-out.

---

## Step 16.1 — Generate AuditEngine

```bash
# From the practice-nexus/ root
rails plugin new engines/audit_engine --mountable --database=postgresql --skip-test
```

Add it to the main app's `Gemfile`:

```ruby
# Gemfile
gem "audit_engine", path: "engines/audit_engine"
```

```bash
bundle install
```

> **AuditEngine is not mounted in routes** — like `EmailEngine`, it is a pure event consumer
> with no HTTP endpoints. It does not need to appear in `config/routes.rb`.

---

## Step 16.2 — AuditLog Migration & Model (AuditEngine)

The audit log is an **append-only** table. Records are never updated or deleted — each Kafka
event becomes one row.

```bash
# From the practice-nexus/ root
rails generate migration CreateAuditEngineAuditLogs \
  user_id:integer \
  action:string \
  changed_fields:text \
  occurred_at:datetime \
  event_id:string \
  topic:string \
  --no-test-framework
```

Edit the generated migration:

```ruby
# db/migrate/XXXXXX_create_audit_engine_audit_logs.rb
class CreateAuditEngineAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_engine_audit_logs do |t|
      t.integer  :user_id,        null: false
      t.string   :action,         null: false   # "created" or "updated"
      t.text     :changed_fields                # JSON string — which fields changed and their new values
      t.datetime :occurred_at,    null: false   # timestamp from the Kafka event payload
      t.string   :event_id,       null: false   # Kafka message offset — used for idempotency
      t.string   :topic,          null: false   # which topic this came from
      t.timestamps
    end

    # Unique constraint → idempotency guard built into the table itself
    # No separate ProcessedEvent table needed — the audit log IS the idempotency record
    add_index :audit_engine_audit_logs, [ :event_id, :topic ], unique: true
    add_index :audit_engine_audit_logs, :user_id
  end
end
```

```bash
rails db:migrate
```

> **Design choice: `changed_fields` as `text` (JSON string)**
> We store it as a JSON string for maximum portability. In a production system you'd use
> `jsonb` (PostgreSQL-specific) for queryability. For learning, `text` keeps the migration
> database-agnostic and avoids the need for a JSON column type concern.

Create the model inside `AuditEngine`:

```ruby
# engines/audit_engine/app/models/audit_engine/audit_log.rb
module AuditEngine
  class AuditLog < ApplicationRecord
    validates :user_id,     presence: true
    validates :action,      presence: true, inclusion: { in: %w[created updated] }
    validates :occurred_at, presence: true
    validates :event_id,    presence: true
    validates :topic,       presence: true
  end
end
```

---

## Step 16.3 — UpdateUser Input Type (UserEngine)

A **partial update input** makes all data fields optional — the client sends only what it wants
to change. The `id` is the only required field (you need to know *which* user to update).

```ruby
# app/graphql/user_engine/types/update_user_input.rb
module UserEngine
  module Types
    class UpdateUserInput < GraphQL::Schema::InputObject
      description "Input fields for updating an existing user. All data fields are optional — only send what should change."

      argument :id,    Integer, required: true,  description: "ID of the user to update"
      argument :name,  String,  required: false, description: "New full name (omit to leave unchanged)"
      argument :email, String,  required: false, description: "New email address (omit to leave unchanged)"
    end
  end
end
```

> **`required: false` vs `required: true`**
> In `CreateUserInput`, both `name` and `email` are `required: true` — a user cannot exist
> without them. In `UpdateUserInput`, they're `required: false` — the client can send just
> `{ id: 1, email: "new@example.com" }` to change only the email. GraphQL will pass `nil`
> for omitted optional arguments, which you then filter out before updating.

---

## Step 16.4 — UserUpdatedProducer (UserEngine)

The producer publishes a `user.updated` event after a successful update. The payload includes
the user's current state and which fields were changed — useful for consumers that only care
about specific changes.

```ruby
# app/events/user_engine/events/user_updated_producer.rb
module UserEngine
  module Events
    class UserUpdatedProducer
      TOPIC = "user.updated".freeze

      # .call(user, changed_fields) is the single entry point
      # changed_fields: hash of { field_name => new_value } for fields that were actually updated
      def self.call(user, changed_fields)
        message = {
          event:          "user.updated",
          user_id:        user.id,
          name:           user.name,
          email:          user.email,
          changed_fields: changed_fields,   # e.g. { "email" => "new@example.com" }
          occurred_at:    user.updated_at.iso8601
        }.to_json

        Karafka.producer.produce_sync(
          topic:   TOPIC,
          payload: message,
          key:     user.id.to_s   # same key as user.created → same partition → ordered events per user
        )
      end
    end
  end
end
```

> **Why pass `changed_fields` explicitly?**
> After `user.save`, ActiveRecord's `previous_changes` contains what changed. Passing it
> explicitly makes the producer a pure function (no hidden AR state dependency) and keeps
> the Kafka payload self-describing — a consumer can act on `changed_fields` without
> fetching the user from a database.

---

## Step 16.5 — UpdateUser Mutation (UserEngine)

```ruby
# app/graphql/user_engine/mutations/update_user.rb
module UserEngine
  module Mutations
    class UpdateUser < GraphQL::Schema::Mutation
      description "Update an existing user's name and/or email"

      argument :input, Types::UpdateUserInput, required: true

      field :user,   Types::UserType, null: true
      field :errors, [ String ],      null: false

      def resolve(input:)
        user = UserEngine::User.find_by(id: input[:id])

        return { user: nil, errors: [ "User not found" ] } if user.nil?

        # Build only the attributes the client actually sent (reject nil values)
        attrs = {}
        attrs[:name]  = input[:name]  unless input[:name].nil?
        attrs[:email] = input[:email] unless input[:email].nil?

        if attrs.empty?
          return { user: user, errors: [ "No fields provided to update" ] }
        end

        if user.update(attrs)
          # user.previous_changes returns { "field" => [old_value, new_value] }
          # We only want the new values for the changed fields
          changed = user.previous_changes
                        .except("updated_at")
                        .transform_values(&:last)

          UserEngine::Events::UserUpdatedProducer.call(user, changed)

          { user: user, errors: [] }
        else
          { user: nil, errors: user.errors.full_messages }
        end
      end
    end
  end
end
```

> **`user.previous_changes` vs `user.changes`**
> - `user.changes` — available *before* save; shows pending changes
> - `user.previous_changes` — available *after* save; shows what was just persisted
> Call `previous_changes` after `user.update` returns `true`.

---

## Step 16.6 — Wire UpdateUser into MutationType

```ruby
# app/graphql/types/mutation_type.rb
module Types
  class MutationType < Types::BaseObject
    field :create_user, mutation: UserEngine::Mutations::CreateUser
    field :update_user, mutation: UserEngine::Mutations::UpdateUser  # ← add this
  end
end
```

---

## Step 16.7 — AuditEngine Consumer (Multi-topic)

One consumer class handles events from both `user.created` and `user.updated`. It branches on
the `event` field in the payload to write the correct action to the audit log.

```ruby
# app/consumers/audit_engine/consumers/user_event_consumer.rb
module AuditEngine
  module Consumers
    class UserEventConsumer < Karafka::BaseConsumer
      def consume
        messages.each do |message|
          process_event(message)
        end
      end

      private

      def process_event(message)
        payload = message.payload.with_indifferent_access
        payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)

        Rails.logger.info "[AuditEngine] Received #{payload[:event]} for user_id=#{payload[:user_id]}"

        # Idempotency check — the unique index on [event_id, topic] will also enforce this
        # at the DB level, but we check first to avoid unnecessary DB writes
        return if AuditEngine::AuditLog.exists?(event_id: message.offset, topic: message.topic)

        action = case payload[:event]
                 when "user.created" then "created"
                 when "user.updated" then "updated"
                 else
                   Rails.logger.warn "[AuditEngine] Unknown event type: #{payload[:event]}"
                   return
                 end

        AuditEngine::AuditLog.create!(
          user_id:        payload[:user_id],
          action:         action,
          changed_fields: payload[:changed_fields]&.to_json,
          occurred_at:    payload[:occurred_at],
          event_id:       message.offset,
          topic:          message.topic
        )

        Rails.logger.info "[AuditEngine] Audit log written: user_id=#{payload[:user_id]} action=#{action}"
      end
    end
  end
end
```

> **Why one class for two topics?**
> Both events share the same business concern (auditing user changes) and the same storage
> (audit_engine_audit_logs). A single class avoids duplicating the idempotency + persistence
> logic. The `case payload[:event]` branch is the only per-topic variation.

---

## Step 16.8 — Wire Topics in karafka.rb (Fan-out via Consumer Groups)

This is the most important step for understanding Kafka fan-out.

```ruby
# karafka.rb
class KarafkaApp < Karafka::App
  setup do |config|
    kafka_config = {}
    kafka_config[:'bootstrap.servers'] = ENV.fetch('KAFKA_BROKER', 'kafka:9092')
    kafka_config[:'auto.offset.reset'] = 'earliest'
    config.kafka = kafka_config
    config.client_id = 'practice_nexus'
  end

  routes.draw do
    # ── Consumer Group 1: Email Service ─────────────────────────────────────
    # Sends a welcome email when a user is created.
    consumer_group :email_service do
      topic 'user.created' do
        consumer EmailEngine::Consumers::UserCreatedConsumer
      end
    end

    # ── Consumer Group 2: Audit Service ─────────────────────────────────────
    # Writes an audit log entry for every user lifecycle event.
    # Subscribes to TWO topics — both feed the same consumer class.
    consumer_group :audit_service do
      topic 'user.created' do
        consumer AuditEngine::Consumers::UserEventConsumer
      end

      topic 'user.updated' do
        consumer AuditEngine::Consumers::UserEventConsumer
      end
    end
  end
end

Karafka.monitor.subscribe('error.occurred') do |event|
  puts "KARAFKA ERROR: #{event[:error].class}: #{event[:error].message}"
  puts event[:error].backtrace.join("\n")
end
```

> **How consumer groups create fan-out:**
> Kafka delivers each message to **every consumer group** that subscribes to a topic.
> `email_service` and `audit_service` are independent groups, so when a `user.created`
> message arrives, Kafka delivers it to both — neither group blocks or is aware of the other.
>
> ```
> topic: user.created
>   │
>   ├──▶ consumer_group: email_service → UserCreatedConsumer → welcome email
>   └──▶ consumer_group: audit_service → UserEventConsumer   → audit log row
> ```

---

## Step 16.9 — Update Engine Autoload Paths

Tell the main Rails app where to find `AuditEngine`'s files.

```ruby
# engines/audit_engine/lib/audit_engine/engine.rb
module AuditEngine
  class Engine < ::Rails::Engine
    isolate_namespace AuditEngine

    config.autoload_paths += %W[
      #{root}/app/consumers
      #{root}/app/models
    ]
  end
end
```

---

## Step 16.10 — Run and Verify

### Start the stack

```bash
docker compose up --build -d
docker compose exec web rails db:migrate
```

### Test the updateUser mutation in GraphiQL (http://localhost:3000/graphiql)

```graphql
# First, create a user
mutation {
  createUser(input: { name: "Alice", email: "alice@example.com" }) {
    user { id name email }
    errors
  }
}

# Then update only the email (leave name unchanged)
mutation {
  updateUser(input: { id: 1, email: "alice-new@example.com" }) {
    user { id name email }
    errors
  }
}

# Try an update with no data fields (should return an error)
mutation {
  updateUser(input: { id: 1 }) {
    user { id }
    errors
  }
}

# Try updating a non-existent user (should return "User not found")
mutation {
  updateUser(input: { id: 9999, name: "Ghost" }) {
    user { id }
    errors
  }
}
```

### Inspect Kafka messages in Kafdrop (http://localhost:9000)

```
Topics → user.created → View Messages   ← should show createUser event
Topics → user.updated → View Messages   ← should show updateUser event
```

### Verify audit logs in the Rails console

```bash
docker compose exec web rails console
```

```ruby
# View all audit log entries
AuditEngine::AuditLog.all
# => [
#   #<AuditEngine::AuditLog user_id: 1, action: "created", changed_fields: nil, ...>,
#   #<AuditEngine::AuditLog user_id: 1, action: "updated", changed_fields: '{"email":"alice-new@example.com"}', ...>
# ]

# Check what fields changed in the update
log = AuditEngine::AuditLog.where(action: "updated").last
JSON.parse(log.changed_fields)
# => { "email" => "alice-new@example.com" }

# Confirm idempotency: replaying the same event produces no duplicate
AuditEngine::AuditLog.count
# => 2 (not 4, even if worker restarted and re-read from earliest offset)
```

### Verify fan-out: both consumers received the user.created event

```ruby
# EmailEngine received it → welcome email sent
ActionMailer::Base.deliveries.last
# => #<Mail::Message to: ["alice@example.com"] subject: "Welcome to Nexus, Alice!">

# AuditEngine also received it → audit log entry exists
AuditEngine::AuditLog.find_by(action: "created", user_id: 1)
# => #<AuditEngine::AuditLog ...> — both consumers got the same message independently
```

---

## Final File Structure (New Files Only)

```
practice-nexus/
├── karafka.rb                                                  ✓ consumer_group blocks added
├── app/
│   ├── consumers/
│   │   └── audit_engine/consumers/
│   │       └── user_event_consumer.rb                         ✓ new — multi-topic consumer
│   ├── events/
│   │   └── user_engine/events/
│   │       └── user_updated_producer.rb                       ✓ new — publishes user.updated
│   └── graphql/
│       ├── types/
│       │   └── mutation_type.rb                               ✓ update_user field added
│       └── user_engine/
│           ├── types/
│           │   └── update_user_input.rb                       ✓ new — partial update input
│           └── mutations/
│               └── update_user.rb                             ✓ new — updateUser mutation
├── db/migrate/
│   └── XXXXXX_create_audit_engine_audit_logs.rb               ✓ new migration
└── engines/
    └── audit_engine/
        ├── app/models/audit_engine/
        │   └── audit_log.rb                                   ✓ new model
        ├── lib/audit_engine/
        │   └── engine.rb                                      ✓ autoload_paths added
        └── audit_engine.gemspec                               ✓ auto-generated
```

---

## Mental Model Summary

```
GraphQL Layer:
  updateUser mutation (optional fields) → finds user → user.update(attrs) → publishes user.updated

Kafka Layer:
  topic: user.created                      topic: user.updated
       │                                         │
       ├── consumer_group: email_service         │
       │   └── UserCreatedConsumer               │
       │       └── sends welcome email           │
       │                                         │
       └── consumer_group: audit_service ────────┘
           └── UserEventConsumer (handles both topics)
               └── AuditLog.create! (append-only)

Database:
  user_engine_users          ← source of truth (mutable)
  audit_engine_audit_logs    ← event history (append-only, never updated)
```

## What You Learned

| Concept | Where it appears |
|---------|-----------------|
| Optional GraphQL arguments (`required: false`) | `UpdateUserInput` — partial update pattern |
| `user.previous_changes` after save | `UpdateUser#resolve` — what actually changed |
| Publishing to a second Kafka topic | `UserUpdatedProducer` → `user.updated` |
| **Fan-out via consumer groups** | `karafka.rb` — two groups both reading `user.created` |
| One consumer class, multiple topics | `UserEventConsumer` registered under two `topic` blocks |
| Idempotency via unique DB index | `audit_engine_audit_logs` unique index on `[event_id, topic]` |
| Event-driven audit trail | Audit history built from Kafka events, not application polls |
