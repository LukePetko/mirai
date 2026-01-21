# Build stage
FROM elixir:1.17-otp-27-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

# Runtime stage - use matching Erlang Alpine image
FROM erlang:27-alpine AS runtime

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/mirai ./

RUN mkdir -p /app/data

ENV HOME=/app

ENTRYPOINT ["/app/bin/mirai"]
CMD ["start"]
