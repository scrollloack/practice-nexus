# 06 — Rails Engine Creation

## Concept: What Is a Rails Engine?

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

## Create the Engines Directory

```bash
# From the nexus/ root
mkdir -p engines
```

## Generate `UserEngine`

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

## Generate `EmailEngine`

```bash
rails plugin new engines/email_engine --mountable --database=postgresql --skip-test
```

## Reference Engines from Main App's `Gemfile`

Engines are referenced as local gems using `path:`:

```ruby
# Gemfile (in nexus/ root)
gem "user_engine",  path: "engines/user_engine"
gem "email_engine", path: "engines/email_engine"
```

```bash
bundle install
```

## Mount Engines in `config/routes.rb`

`EmailEngine` is a pure Kafka consumer — it has no HTTP endpoints, so we do not mount it.
Only `UserEngine` (which exposes user-related routes) is mounted.

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

## Create the User Model

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

## Create the Mailer (EmailEngine)

`EmailEngine` uses Rails' built-in **ActionMailer** — no extra gem required.

```bash
# Generate a mailer inside EmailEngine
cd engines/email_engine
rails generate mailer UserMailer welcome --no-test-framework
cd ../..
```

This creates:
```
engines/email_engine/app/mailers/email_engine/
└── user_mailer.rb
engines/email_engine/app/views/email_engine/user_mailer/
├── welcome.html.erb
└── welcome.text.erb
```

The mailer:
```ruby
# engines/email_engine/app/mailers/email_engine/user_mailer.rb
module EmailEngine
  class UserMailer < ActionMailer::Base
    default from: "noreply@nexus.app"

    def welcome(user_id:, name:, email:)
      @name   = name
      @email  = email
      mail(to: email, subject: "Welcome to Nexus, #{name}!")
    end
  end
end
```

Plain-text email body:
```erb
<%# engines/email_engine/app/views/email_engine/user_mailer/welcome.text.erb %>
Hi <%= @name %>,

Your account has been created successfully.
Email: <%= @email %>

Welcome aboard!
— The Nexus Team
```

### ActionMailer Delivery in Development

Rails stores sent emails in memory during development/test when delivery is set to `:test`.
Add this to `config/environments/development.rb`:

```ruby
# config/environments/development.rb
config.action_mailer.delivery_method = :test
config.action_mailer.perform_deliveries = true
```

> **Why `:test`?** No external mail server needed. Delivered emails accumulate in
> `ActionMailer::Base.deliveries` — an in-memory array you can inspect in the Rails console.

## Verify the Setup

```bash
# Open Rails console
rails console

# Create a user
user = UserEngine::User.create!(name: "Alice", email: "alice@example.com")
# => #<UserEngine::User id: 1, name: "Alice", email: "alice@example.com">

# Manually send a welcome email
EmailEngine::UserMailer.welcome(user_id: user.id, name: user.name, email: user.email).deliver_now

# Inspect sent emails
ActionMailer::Base.deliveries.last
# => #<Mail::Message to: ["alice@example.com"], subject: "Welcome to Nexus, Alice!">
```
