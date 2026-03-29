# 08 — Kafka Fundamentals

## Concept: What Is Kafka?

**Apache Kafka** is a distributed event streaming platform. It acts as a persistent,
ordered log of events that multiple services can read from independently.

Think of it like a post office:
- A **Producer** drops a letter (event) into a **mailbox** (topic)
- Any number of **Consumers** can pick up letters from that mailbox
- Letters stay in the mailbox for a configurable period — consumers can re-read them

## Core Kafka Vocabulary

| Term | Definition | Our Example |
|------|-----------|-------------|
| **Topic** | A named channel/category of events | `user.created` |
| **Producer** | Code that publishes events to a topic | `UserEngine` after saving a user |
| **Consumer** | Code that subscribes to a topic and processes events | `EmailEngine` listening for new users and sending welcome emails |
| **Message/Event** | The payload sent through Kafka (usually JSON) | `{ "user_id": 1, "email": "alice@example.com" }` |
| **Offset** | The position of a message in a topic (like a line number) | Used for idempotency |
| **Consumer Group** | A group of consumers sharing the workload of a topic | All EmailEngine instances share one group |
| **Partition** | A topic can be split into partitions for parallelism | We use 1 partition for simplicity |

## Why Kafka for Pub/Sub?

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

## Configure Karafka

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

## Step 8.1 — Define the Topic

Topics in Kafka are auto-created when a producer first publishes to them
(we enabled `KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"` in docker-compose).

Our topic name: **`user.created`**

Convention: Use dot-notation `<service>.<event>` — it's readable and groups related
events visually in Kafdrop.

## Step 8.2 — Create a Kafka Producer (UserEngine)

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

## Step 8.3 — Create a Kafka Consumer (EmailEngine)

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

## Step 8.4 — Start the Karafka Consumer Worker

The web server (`rails server`) handles HTTP. Karafka consumers run separately.
The `worker` service in `docker-compose.yml` handles this automatically (see Section 4).

To run manually outside Docker:
```bash
bundle exec karafka server
```

## Step 8.5 — Event Idempotency

### What Is Idempotency?

An operation is **idempotent** if running it multiple times produces the same result
as running it once.

**Why does this matter in Kafka?**

Kafka guarantees "at-least-once" delivery by default. This means:
- Under network failures or consumer crashes, **the same message may be delivered more than once**
- Without idempotency protection, you'd send duplicate emails

```
Timeline without idempotency protection:
  Message delivered → welcome email sent → consumer crashes before committing offset
  Message re-delivered → welcome email sent AGAIN → duplicate email!

Timeline with idempotency protection:
  Message delivered → idempotency check → email sent → offset committed
  Message re-delivered → idempotency check → already processed → SKIP → safe!
```

### Idempotency Strategies

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

### Migration for `ProcessedEvent`

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

## Kafka Mental Model Summary

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
