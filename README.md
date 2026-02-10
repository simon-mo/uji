# Uji

A universal JSON ingestor built on [Vector](https://vector.dev). Accept arbitrary JSON via HTTP, store it in Google Cloud Storage (date-partitioned), and forward it to configurable HTTP endpoints. No application code — the entire pipeline is Vector YAML config.

## Quick start

### Prerequisites

- [Vector](https://vector.dev/docs/setup/installation/) (`brew install vectordotdev/brew/vector` on macOS)
- [Docker](https://docs.docker.com/get-docker/) (for building/deploying)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) (for GCP deployment)
- [gh CLI](https://cli.github.com/) (used by `deploy.sh` to verify CI)

### Run locally

```bash
vector --config vector_local.yaml
```

Then send a JSON event:

```bash
curl -X POST http://127.0.0.1:8080 \
  -H "Content-Type: application/json" \
  -d '{"event": "signup", "user": "alice"}'
```

You'll see the transformed output in your terminal — the original payload nested under `message` with request metadata alongside it.

### Run with HTTP forwarding

To forward events to a local endpoint (e.g. for development):

```bash
FORWARD_URL=http://localhost:9090 vector --config vector_local.yaml
```

## How it works

```
HTTP POST --> Vector HTTP source --> modify transform --> GCS sink (production)
                                         |           --> HTTP forward sink
                                         |           --> console sink (sampled)
                                         v
                                  { "message": <your JSON>,
                                    "request_metadata": { path, headers, ... } }
```

1. **Receive** — Vector listens for HTTP POST requests with JSON bodies
2. **Transform** — The `modify` remap separates your payload into `message` and captures request metadata (path, headers, timestamp)
3. **Store** — In production, events are written to GCS with date-partitioned keys (`year=YYYY/month=MM/day=DD/`)
4. **Forward** — Events are POSTed to a configurable HTTP endpoint with bearer auth, designed for [Databricks ZeroBus REST ingest](https://docs.databricks.com/) (sends `unity-catalog-endpoint` and `x-databricks-zerobus-table-name` headers)
5. **Log** — A sampled stream is printed to console; errors/warnings from Vector internals are also logged as structured JSON

## Deploy to GCP

```bash
./deploy.sh
```

The script will:
1. Verify the Docker image was built by CI for the current commit
2. Prompt for service name, GCS bucket, and optional forwarding configuration
3. Create the GCS bucket (with confirmation) if it doesn't exist
4. Deploy to Cloud Run with the appropriate environment variables

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `HOST` | No | Bind address (default: `0.0.0.0`) |
| `PORT` | No | Bind port (default: `8080`) |
| `GCS_BUCKET_NAME` | Production | GCS bucket for event storage |
| `GCS_BATCH_MAX_EVENTS` | No | Events per GCS batch (default: `1000`) |
| `GCS_BATCH_TIMEOUT_SECS` | No | Max seconds before flushing a GCS batch (default: `300`) |
| `FORWARD_URL` | Production | HTTP endpoint to forward events to |
| `FORWARD_AUTH_TOKEN` | Production | Bearer token for the forwarding endpoint |
| `DATABRICKS_WORKSPACE_URL` | No | Sent as `unity-catalog-endpoint` header |
| `DATABRICKS_TABLE_NAME` | No | Sent as `x-databricks-zerobus-table-name` header |
| `VECTOR_LOG` | No | Vector log level (set to `info` by `deploy.sh`) |

## Testing

Run the integration test to verify the full pipeline locally:

```bash
python3 test_integration.py
```

This starts a catch-all HTTP server, runs Vector, sends a test payload, and asserts that the forwarded request has the correct body structure, authorization, and headers.

## CI/CD

Every push to `main` builds and pushes a Docker image to Docker Hub (`simonmok/uji`) tagged with the git SHA. The deploy script checks this succeeded before deploying.
