# Dockerfile
FROM ruby:3.4.9-slim

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  libyaml-dev \
  libxml2-dev \
  libxslt1-dev \
  libffi-dev \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libjemalloc-dev \
  libvips-dev \
  imagemagick \
  nodejs \
  git \
  curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Match local Bundler version
RUN gem install bundler:4.0.9

# Copy app
COPY . .

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]