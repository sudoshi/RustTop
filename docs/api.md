# RustTop API

RustTop's HTTP API is disabled by default. It runs in headless mode when explicitly enabled with `--api` or `[api].enabled = true`.

## Start

```bash
rust_top --api --api-addr 127.0.0.1:9977 --api-token "$RUSTTOP_API_TOKEN"
```

All metric-bearing endpoints require a bearer token. Non-loopback binds are allowed only when a token is configured:

```bash
rust_top --api --api-addr 0.0.0.0:9977 --api-token "$RUSTTOP_API_TOKEN"
curl -H "Authorization: Bearer $RUSTTOP_API_TOKEN" http://127.0.0.1:9977/api/v1/snapshot
```

## Config

```toml
[api]
enabled = false
address = "127.0.0.1:9977"
token = "local-development-token"
```

## Endpoints

| Endpoint | Auth | Content type | Description |
| --- | --- | --- | --- |
| `GET /health` | No | `application/json` | API health, version, and schema metadata. |
| `GET /api/v1/snapshot` | Required | `application/json` | Versioned current system snapshot. |
| `GET /api/v1/alerts` | Required | `application/json` | Active sustained-threshold alerts. |
| `GET /metrics` | Required | `text/plain; version=0.0.4` | Prometheus text metrics. |

## Examples

Get collector health:

```bash
curl http://127.0.0.1:9977/health
```

Get top CPU processes:

```bash
curl -s -H "Authorization: Bearer $RUSTTOP_API_TOKEN" http://127.0.0.1:9977/api/v1/snapshot \
  | jq '.top_processes | sort_by(.cpu_usage) | reverse | .[:5]'
```

Watch active alerts:

```bash
watch -n 2 'curl -s -H "Authorization: Bearer $RUSTTOP_API_TOKEN" http://127.0.0.1:9977/api/v1/alerts | jq .alerts'
```

Scrape Prometheus metrics:

```bash
curl -H "Authorization: Bearer $RUSTTOP_API_TOKEN" http://127.0.0.1:9977/metrics
```
