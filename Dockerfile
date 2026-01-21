# Build stage
FROM elixir:1.17-otp-27-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build env
ENV MIX_ENV=prod

# Copy dependency files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.20 AS runtime

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache libstdc++ ncurses-libs

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/mirai ./

# Create data directory for persistent state
RUN mkdir -p /app/data

ENV HOME=/app

ENTRYPOINT ["/app/bin/mirai"]
CMD ["start"]
