# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Uji is a universal JSON ingestor built on [Vector](https://vector.dev). It accepts arbitrary JSON via HTTP, stores it in Google Cloud Storage (date-partitioned), and forwards it to configurable HTTP endpoints. There is no application source code — the entire pipeline is defined in Vector YAML configuration files.

## Common Commands

**Run locally:**
```bash
vector --config vector_local.yaml
```

**Build Docker image:**
```bash
docker build -t uji .
```

**Deploy to GCP (Cloud Run + GCS):**
```bash
cp deploy_config.example.yaml deploy_config.yaml  # fill in your values
./deploy.sh deploy_config.yaml
```
The deploy script reads configuration from a YAML file. Requires `yq` (`brew install yq`). See `deploy_config.example.yaml` for the expected format.

**Run integration tests:**
```bash
python3 test_integration.py
```
Tests the full pipeline locally: starts a catch-all HTTP server, runs Vector, sends a test payload, and verifies the forwarded request has correct body, auth, and headers.

**Test locally (send a JSON event):**
```bash
curl -X POST http://127.0.0.1:8080 -H "Content-Type: application/json" -d '{"key": "value"}'
```

## Architecture

**Data flow:** HTTP POST → Vector HTTP source → `modify` transform (parse JSON, separate metadata) → `sample` transform → console sink + GCS sink + HTTP forward sink

**Key files:**
- `vector_config.yaml` — Production pipeline config (HTTP source → GCS + console sinks)
- `vector_local.yaml` — Local dev config (HTTP source → console sink only, API enabled)
- `deploy.sh` — GCP deployment: creates GCS bucket, deploys Cloud Run service
- `Dockerfile` — Based on `timberio/vector:latest-alpine`, runs production config

**Environment variables:**
- `HOST` / `PORT` — Bind address and port (defaults: `0.0.0.0` / `8080`)
- `GCS_BUCKET_NAME` — Required in production for the GCS sink
- `GCS_BATCH_MAX_EVENTS` / `GCS_BATCH_TIMEOUT_SECS` — GCS batching (defaults: 1000 / 300)
- `FORWARD_URL` — Target HTTP endpoint URL for the forwarding sink (required in production)
- `FORWARD_AUTH_TOKEN` — Bearer token for the forwarding endpoint (required in production)
- `DATABRICKS_WORKSPACE_URL` — Value for `unity-catalog-endpoint` header
- `DATABRICKS_TABLE_NAME` — Value for `x-databricks-zerobus-table-name` header
- `VECTOR_LOG` — Vector log level (set to `info` in production by `deploy.sh`)

## CI/CD

GitHub Actions (`.github/workflows/docker-publish.yml`) builds and pushes Docker images to Docker Hub (`simonmok/uji`) on every push to main, tagged with the git SHA.
