# Mirai

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mirai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mirai, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mirai>.

## Local runtime API

Mirai can expose a read-only runtime snapshot for local operational tools. The API is disabled
unless a token of at least 32 characters is configured.

```dotenv
MIRAI_RUNTIME_API_BIND=127.0.0.1
MIRAI_RUNTIME_API_PORT=4100
MIRAI_RUNTIME_API_TOKEN=<long-random-secret>
```

Authenticated requests use `Authorization: Bearer <token>`:

```text
GET /health
GET /v1/snapshot
```

The snapshot contains sanitized process health, Home Assistant connection health, bounded recent
action/error events, and automation summaries. It never includes Home Assistant credentials or raw
automation state.

Deployment branch and commit are read from `.mirai-deployment.json` inside
`MIRAI_AUTOMATIONS_PATH`. `MIRAI_AUTOMATIONS_BRANCH` and `MIRAI_AUTOMATIONS_COMMIT` can override
the file when deployment metadata is supplied another way.

