# 10 — Testing the APIs (GraphiQL + Kafdrop)

## Concept: What Are We Testing?

This section is a guided walkthrough — you run each step in order and verify the
expected output. By the end you will have exercised every layer of the stack:

```
GraphiQL (browser) → GraphQL mutation → ActiveRecord → Kafka producer
                                                              ↓
                                                      Kafka topic
                                                              ↓
                                               Karafka consumer → PostgreSQL
```

---

## Step 10.1 — Open GraphiQL

1. Make sure all Docker services are running: `docker compose ps`
2. Open your browser: **http://localhost:3000/graphiql**
3. You should see the GraphiQL IDE with a left panel (query editor) and right panel (results)

> **Tip:** Click the **Docs** button (top right) to explore the auto-generated schema
> documentation. This is introspection — one of GraphQL's superpowers.

---

## Step 10.2 — Introspect the Schema

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

## Step 10.3 — Create a User (Mutation)

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

## Step 10.4 — Verify the Kafka Event in Kafdrop

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

## Step 10.5 — Verify the Consumer Sent the Email

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

## Step 10.6 — Query Users (Query)

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

## Step 10.7 — Test Validation Errors

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

## Step 10.8 — Test Idempotency (Kafka Re-delivery Simulation)

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

## What You've Learned — Final Summary

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
