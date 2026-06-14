# Local inference stack

Run the FastAPI inference backend + telemetry locally — no AWS, no GPU — to
verify the API, Prometheus metrics, and OTLP traces all work before deploying.

Containers (see [docker-compose.yml](docker-compose.yml)):

| Service | URL | Purpose |
|---|---|---|
| `inference` | http://localhost:8080 | the FastAPI app (`/predict`, `/healthz`, `/readyz`, `/metrics`) |
| `prometheus` | http://localhost:9090 | scrapes `inference:8080/metrics` every 5s |
| `grafana` | http://localhost:3000 | views the metrics (anonymous admin; Prometheus pre-wired) |
| `otel-collector` | (logs only) | receives the app's spans; `docker compose logs -f otel-collector` to see them |

## 1. Get a model artifact

The app needs `model.pth` + `model_config.json` + `label_map.json` in `./model`.

**Don't have a trained model?** Generate a random one — enough to exercise the
whole pipeline (predictions are garbage by design):

```bash
cd training
python local/make_dummy_model.py --out local/model --num-classes 10
```

**Have a real one?** Drop the three files into `training/local/model/` (e.g.
`aws s3 cp s3://kinetics-pipeline-dev-checkpoints-533267178572/cnn-lstm/model/ local/model/ --recursive`).

## 2. Bring up the stack

```bash
cd training
docker compose -f local/docker-compose.yml up --build
```

Wait for `inference` to log `Uvicorn running on http://0.0.0.0:8080`, then:

```bash
curl localhost:8080/healthz      # {"status":"ok","model_loaded":true}
curl localhost:8080/metrics      # Prometheus exposition
```

## 3. Send a prediction

### Option A — a real Kinetics-400 clip (the `video_b64` path)

Grab one short clip (any `.mp4` works for a smoke test; a real Kinetics clip from
the CVDF mirror is ideal). Base64-encode it and POST:

```bash
VID=clip.mp4
python - "$VID" <<'PY' > body.json
import base64, json, sys
raw = open(sys.argv[1], "rb").read()
print(json.dumps({"video_b64": base64.b64encode(raw).decode(), "top_k": 5}))
PY
curl -s -X POST localhost:8080/predict \
  -H 'Content-Type: application/json' --data @body.json | jq
```

### Option B — a synthetic clip (no video file, the `clip` path)

A correctly-shaped random tensor `(T, 3, H, W)` exercises the model + metrics
without decoding video:

```bash
python - <<'PY' > body.json
import json, random
T, C, H, W = 16, 3, 224, 224
clip = [[[[random.random() for _ in range(W)] for _ in range(H)] for _ in range(C)] for _ in range(T)]
print(json.dumps({"clip": clip, "top_k": 5}))
PY
curl -s -X POST localhost:8080/predict -H 'Content-Type: application/json' --data @body.json | jq
```

### Postman

`POST http://localhost:8080/predict`, Body → raw → JSON:

```json
{ "video_b64": "<paste base64>", "top_k": 5 }
```

## 4. See that it worked

- **Metrics**: Prometheus → http://localhost:9090 → graph
  `model_prediction_confidence_bucket`, `inference_requests_total`,
  `rate(inference_request_duration_seconds_sum[1m])`. Or Grafana Explore →
  http://localhost:3000.
- **Traces**: `docker compose -f local/docker-compose.yml logs -f otel-collector`
  — you'll see a `predict` span per request (OTLP works end-to-end).

## Teardown

```bash
docker compose -f local/docker-compose.yml down -v
```

> The model dir, dummy artifacts, and request bodies are gitignored
> (`local/model/`, `body.json`).
