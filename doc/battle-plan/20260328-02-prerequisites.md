# 02 — Prerequisites

## Required Tools

| Tool | Version | Check Command |
|------|---------|---------------|
| Ruby | >= 3.2 | `ruby -v` |
| Rails | >= 7.1 | `rails -v` |
| Docker | >= 24 | `docker -v` |
| Docker Compose | >= 2.20 | `docker compose version` |
| Bundler | >= 2.4 | `bundler -v` |

## Install Ruby (via rbenv — recommended)

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

## Install Rails

```bash
gem install rails -v '~> 7.1'
rails -v  # => Rails 7.1.x
```

## Install Docker

Follow the official docs for your OS: https://docs.docker.com/engine/install/

Verify:
```bash
docker -v
docker compose version
```
