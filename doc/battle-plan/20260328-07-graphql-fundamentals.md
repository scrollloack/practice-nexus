# 07 — GraphQL Fundamentals

## Concept: GraphQL vs REST

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

## GraphQL Building Blocks

| Concept | What it is | Rails Analogy |
|---------|-----------|---------------|
| **Type** | Shape of an object (what fields it has) | ActiveRecord model shape |
| **Query** | Read operation | `GET` request / `index`/`show` actions |
| **Mutation** | Write operation | `POST`/`PUT`/`DELETE` requests |
| **Resolver** | The method that fetches/writes data | Controller action body |
| **Input Type** | Structured input for mutations | Strong params / form object |
| **Schema** | Root definition — wires queries + mutations together | `routes.rb` |

## Initialize GraphQL in the Main App

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

## Step 7.1 — Define a GraphQL Type

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

## Step 7.2 — Define a Query (Read Operation)

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

> **Why no EmailEngine resolvers here?**
> `EmailEngine` is a pure event consumer — it reacts to Kafka events and sends emails.
> It exposes no data for clients to query, so it has no GraphQL types or resolvers.

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

## Step 7.3 — Define an Input Type

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

## Step 7.4 — Define a Mutation (Write Operation)

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

## Step 7.5 — Wire the Schema Together

```ruby
# app/graphql/nexus_schema.rb
class NexusSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # Enable lazy loading for N+1 prevention (optional but good practice)
  use GraphQL::Dataloader
end
```

## Summary: How GraphQL Maps to ActiveRecord

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
