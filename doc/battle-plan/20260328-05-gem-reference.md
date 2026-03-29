# 05 — Gem Reference

> Important gems used in this project only — those directly related to the learning goals.

## Add to `Gemfile`

```ruby
# Gemfile

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.0"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"           # PostgreSQL adapter for ActiveRecord
gem "puma", "~> 6.0"         # Web server
gem "sprockets-rails"        # Asset pipeline (required by graphiql-rails)

# GraphQL
gem "graphql", "~> 2.3"      # Core GraphQL-Ruby library
gem "graphiql-rails"         # Browser-based GraphQL IDE (development only)

# Kafka / Pub-Sub
gem "karafka", "~> 2.3"      # Kafka client — producers + consumers (Rails-native)

# Engines (local path references)
gem "user_engine",  path: "engines/user_engine"
gem "email_engine", path: "engines/email_engine"

group :development, :test do
  gem "debug"
end
```

```bash
bundle install
```

## Gem Roles Explained

| Gem | Role | Used In |
|-----|------|---------|
| `rails` | Framework — routing, ActiveRecord, middleware | Everywhere |
| `pg` | PostgreSQL database adapter. Translates ActiveRecord calls to SQL | All engines |
| `puma` | Multi-threaded web server. Handles concurrent HTTP requests | Main app |
| `sprockets-rails` | Asset pipeline. Required by graphiql-rails since we use `--api` mode | Main app |
| `graphql` | Defines GraphQL schema, types, mutations, queries, and resolvers | Main app + engines |
| `graphiql-rails` | Mounts an interactive browser UI at `/graphiql` to test queries | Main app (dev only) |
| `karafka` | Kafka client framework for Ruby/Rails. Manages producers and consumers with a Rails-like DSL | UserEngine (producer), EmailEngine (consumer) |
