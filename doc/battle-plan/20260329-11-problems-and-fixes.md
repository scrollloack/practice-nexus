# 🛡️ Practice Nexus — Problem and fixes Documentation
> A complete record of every problem encountered and fix applied during the Docker + Rails + Kafka + Karafka setup on WSL Ubuntu.

---

## Environment
| Tool | Version |
|------|---------|
| OS | WSL Ubuntu (Windows) |
| Ruby | 3.4.9 |
| Rails | 7.2.3.1 |
| Bundler | 4.0.9 |
| Karafka | 2.5.8 |
| Docker | Compose v2 |

---

## Problem 1 — `docker-compose.yml` had obsolete `version` key
**Error:**
```
WARN: the attribute `version` is obsolete, it will be ignored
```
**Fix:** Remove the top-level `version: "3.9"` key from `docker-compose.yml`. Modern Docker Compose does not require it.

---

## Problem 2 — `bitnami/zookeeper:latest` not found on Docker Hub
**Error:**
```
failed to resolve reference "docker.io/bitnami/zookeeper:latest": not found
```
**Root Cause:** Bitnami discontinued their standalone Zookeeper image on Docker Hub and migrated all images to `ghcr.io`.

**Fix:** Switched from Bitnami to Confluent images which are reliably hosted on Docker Hub:
```yaml
zookeeper:
  image: confluentinc/cp-zookeeper:7.6.0

kafka:
  image: confluentinc/cp-kafka:7.6.0
```
> Note: Confluent env vars use `KAFKA_*` prefix instead of Bitnami's `KAFKA_CFG_*` prefix.

---

## Problem 3 — Dockerfile using wrong Ruby version + missing Bundler
**Error:**
```
Bundler 2.5.22 is running, but your lockfile was generated with 4.0.9
```
**Root Cause:** `Dockerfile` was using `ruby:3.3-slim` but local Ruby is `3.4.9`. Also missing explicit Bundler installation.

**Fix:**
```dockerfile
FROM ruby:3.4.9-slim
RUN gem install bundler:4.0.9
```

---

## Problem 4 — Missing `libyaml-dev` causing `psych` gem build failure
**Error:**
```
yaml.h not found
Gem::Ext::BuildError: ERROR: Failed to build gem native extension (psych-5.3.1)
```
**Root Cause:** `ruby:3.4.9-slim` is a minimal image missing system headers needed by native gems.

**Fix:** Added full set of common Rails native extension dependencies to Dockerfile:
```dockerfile
RUN apt-get update -qq && apt-get install -y \
  build-essential libpq-dev libyaml-dev libxml2-dev \
  libxslt1-dev libffi-dev libssl-dev libreadline-dev \
  zlib1g-dev libjemalloc-dev libvips-dev imagemagick \
  nodejs git curl \
  && rm -rf /var/lib/apt/lists/*
```

---

## Problem 5 — Sprockets missing `manifest.js`
**Error:**
```
Expected to find a manifest file in `app/assets/config/manifest.js`
(Sprockets::Railtie::ManifestNeededError)
```
**Root Cause:** `graphiql-rails` requires `sprockets-rails` which mandates a manifest file. File was never created.

**Fix:**
```bash
mkdir -p app/assets/images app/assets/stylesheets
cat > app/assets/config/manifest.js << 'EOF'
//= link_tree ../images
//= link graphiql/rails/application.css
//= link graphiql/rails/application.js
EOF
```
Also add to `config/environments/development.rb`:
```ruby
require "sprockets/railtie"
```

---

## Problem 6 — GraphQL schema double `mutation` registration
**Error:**
```
Second definition of `mutation(...)` is invalid, already configured with Types::MutationType
```
**Root Cause:** `query_type.rb` was referencing engine resolvers using wrong keyword (`resolvers:` instead of `resolver:`) causing Zeitwerk to reload the schema, registering `mutation` twice.

**Fix:**
```ruby
# Wrong
field :users, resolvers: UserEngine::Resolvers::UsersResolver

# Correct
field :users, resolver: UserEngine::Resolvers::UsersResolver
```
Also moved engine resolver files from `app/graphql/user_engine/` into the engine itself at `engines/user_engine/app/graphql/user_engine/resolvers/`.

---

## Problem 7 — Rails engine migrations not picked up by `rails db:migrate`
**Symptom:** Running `rails db:migrate` from root showed no migrations from engines.

**Fix:** Add engine migration paths to `config/application.rb`:
```ruby
config.paths["db/migrate"].concat(
  Dir.glob(Rails.root.join("engines/*/db/migrate"))
)
```

---

## Problem 8 — Git refusing to add engine directories
**Error:**
```
error: 'engines/email_engine/' does not have a commit checked out
fatal: adding files failed
```
**Root Cause:** `rails plugin new` initializes a `.git` folder inside each engine, making them appear as git submodules.

**Fix:**
```bash
rm -rf engines/email_engine/.git
rm -rf engines/user_engine/.git
git add .
```

---

## Problem 9 — Kafka connection refused in worker container
**Error:**
```
kafka:9092/bootstrap: Connect to ipv4#172.18.0.4:9092 failed: Connection refused
```
**Root Cause:** Race condition — worker container was starting before Kafka was fully ready to accept connections.

**Fix:** Added healthcheck to Kafka and made worker wait for it:
```yaml
kafka:
  healthcheck:
    test: ["CMD", "kafka-topics", "--bootstrap-server", "localhost:9092", "--list"]
    interval: 10s
    timeout: 10s
    retries: 10
    start_period: 30s

worker:
  depends_on:
    kafka:
      condition: service_healthy
    db:
      condition: service_started
```

---

## Problem 10 — Worker logs completely blank / stdout not flushing
**Symptom:** `docker compose logs -f worker` showed only Karafka banner, no processing output.

**Fix:** Created `config/initializers/stdout_sync.rb`:
```ruby
$stdout.sync = true
$stderr.sync = true
```
> Note: `RUBYOPT: "-e STDOUT.sync=true"` does NOT work — `-e` is not a valid `RUBYOPT` flag.

---

## Problem 11 — Confluent Kafka CLI tools have no `.sh` extension
**Error:**
```
kafka-consumer-groups.sh: executable file not found in $PATH
```
**Fix:** Confluent images drop the `.sh` suffix. Use:
```bash
# Wrong
kafka-consumer-groups.sh

# Correct
kafka-consumer-groups
```

---

## Problem 12 — Consumer group offset never resetting
**Symptom:** `CURRENT-OFFSET: —` even after running reset command. Error: `group 'app' is inactive but current state is Stable`.

**Root Cause:** Both `web` and `worker` containers load the Rails app and hold the consumer group open. Stopping only `worker` is not enough.

**Fix:** Stop both `web` and `worker` before resetting:
```bash
docker compose stop worker web
sleep 15
docker compose exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group app \
  --topic user.created \
  --reset-offsets --to-earliest --execute
docker compose start web worker
```

---

## Problem 13 — Karafka config keys must be symbols, not strings
**Error:**
```
"config.kafka.bootstrap.servers": "All keys under the kafka settings scope need to be symbols"
(Karafka::Errors::InvalidConfigurationError)
```
**Root Cause:** Karafka 2.5.8 strictly requires symbol keys in `config.kafka`. The shorthand `'key':` syntax and `'key' =>` string syntax both fail. RuboCop/ruby-lsp auto-corrects symbol syntax back to string shorthand.

**Fix:** Build the hash programmatically to bypass linter auto-correction:
```ruby
class KarafkaApp < Karafka::App
  setup do |config|
    kafka_config = {}
    kafka_config[:'bootstrap.servers'] = ENV.fetch('KAFKA_BROKER', 'kafka:9092')
    kafka_config[:'auto.offset.reset'] = 'earliest'
    config.kafka = kafka_config
    config.client_id = 'practice_nexus'
  end
end
```
> `hash[:'key'] =` syntax is not subject to RuboCop's hash rocket auto-correction rule.

---

## Problem 14 — Consumer silently failing with `TypeError`
**Error (surfaced via Karafka error monitor):**
```
KARAFKA ERROR: TypeError: no implicit conversion of Hash into String
JSON.parse(message.payload, symbolize_names: true)
```
**Root Cause:** Karafka 2.5.x automatically deserializes message payloads. `message.payload` returns a **Hash**, not a String. Calling `JSON.parse` on it raises `TypeError`.

**Fix:**
```ruby
def process_event(message)
  payload = message.payload
  payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)
  # use payload[:key] or payload["key"] with .with_indifferent_access
  payload = payload.with_indifferent_access
end
```

**To surface silent Karafka errors in future, add to `karafka.rb`:**
```ruby
Karafka.monitor.subscribe('error.occurred') do |event|
  puts "KARAFKA ERROR: #{event[:error].class}: #{event[:error].message}"
  puts event[:error].backtrace.join("\n")
end
```

---

## Final Working Stack Summary

### `docker-compose.yml` key points
- Confluent Kafka + Zookeeper (not Bitnami)
- Kafka healthcheck with `service_healthy` condition on worker
- `KAFKA_HEAP_OPTS` to prevent OOM kills
- Single listener `PLAINTEXT://0.0.0.0:9092` for internal Docker networking

### `Dockerfile` key points
- `ruby:3.4.9-slim` matching local Ruby version
- `gem install bundler:4.0.9` matching local Bundler version
- Full set of native extension system dependencies

### `karafka.rb` key points
- Programmatic hash syntax for symbol keys
- `auto.offset.reset: earliest` for dev convenience
- `error.occurred` monitor subscription for debugging

### Consumer key points
- `message.payload` is already deserialized — never call `JSON.parse` directly on it
- Guard with `if payload.is_a?(String)` for safety
- Use `.with_indifferent_access` for flexible key access
- Use fully namespaced constants: `EmailEngine::ProcessedEvent` not `ProcessedEvent`