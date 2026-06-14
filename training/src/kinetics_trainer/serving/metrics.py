"""Prometheus metrics for the inference service.

Two families are exposed on ``/metrics``:

* **Operational** — request count, latency, in-flight gauge (SLOs, autoscaling).
* **Model performance** — top-1 confidence distribution and predicted-class
  distribution. Both need *no* ground-truth labels at serving time, so they are
  the unsupervised signals that surface model drift / degradation in Grafana.
  True accuracy still requires a labelled feedback loop.
"""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "inference_requests_total",
    "Total inference requests by endpoint and outcome.",
    ["endpoint", "status"],
)

LATENCY = Histogram(
    "inference_request_duration_seconds",
    "End-to-end inference request latency in seconds.",
    ["endpoint"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

IN_PROGRESS = Gauge(
    "inference_in_progress",
    "Inference requests currently being served.",
)

CONFIDENCE = Histogram(
    "model_prediction_confidence",
    "Top-1 softmax confidence of served predictions.",
    buckets=(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0),
)

PREDICTIONS = Counter(
    "model_predictions_total",
    "Predicted top-1 class distribution (label drift signal).",
    ["label"],
)

MODEL_INFO = Gauge(
    "model_info",
    "Loaded model metadata; value is always 1.",
    ["model", "backbone", "num_classes"],
)


def record_prediction(top1_label: str, top1_score: float) -> None:
    """Record the model-performance signals for one served prediction."""
    CONFIDENCE.observe(top1_score)
    PREDICTIONS.labels(label=top1_label).inc()
