# Stage 1: Build the release
FROM elixir:1.18-slim AS builder

# Set environment to production
ENV MIX_ENV=prod

# Install build tools
RUN apt-get update && apt-get install -y build-essential git

# Set working directory
WORKDIR /app

# Fetch dependencies
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get

# Compile
RUN mix deps.compile

# Copy and compile app
COPY . .
RUN mix compile

# Build release
RUN mix release

# Stage 2: Runtime image
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y libssl3 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the release from builder
COPY --from=builder /app/_build/prod/rel/protohacker .

# Ensure correct permissions
RUN chown -R 1000:1000 /app && chmod +x bin/protohacker

# Switch to non-root user
USER 1000

# Expose port (if your app listens on one)
EXPOSE 3001 3003

# Start the app
CMD ["bin/protohacker", "start"]