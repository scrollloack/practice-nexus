# 04 — Docker Setup

## Concept: Why Docker?

Docker lets you run Kafka, PostgreSQL, and Zookeeper locally without installing them
natively. `docker-compose.yml` defines all services in one file so you can spin up
the entire stack with one command.

## Services We Need

| Service | Purpose | Port |
|---------|---------|------|
| `db` | PostgreSQL database | 5432 |
| `zookeeper` | Required by Kafka for cluster coordination | 2181 |
| `kafka` | Message broker — handles topics, producers, consumers | 9092 |
| `kafdrop` | Web UI to inspect Kafka topics and messages | 9000 |
| `web` | Rails application | 3000 |

## Create `Dockerfile`

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

## Create `docker-compose.yml`

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

volumes:
  postgres_data:
```

## Start the Infrastructure

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

## Useful Docker Commands

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
