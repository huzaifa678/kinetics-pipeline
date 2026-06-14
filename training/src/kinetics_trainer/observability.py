"""Optional, no-op-by-default observability: structured logging and OTel tracing.

Structured logging is always on; OpenTelemetry tracing runs only when configured.

Design contract — mirrors tracking.Tracker's "disabled unless configured":

* Logging is always available via get_logger(); it's plain stdlib logging, so it
  has no extra dependencies and works in local runs, CI, and inside pods.
* Tracing activates ONLY when OTEL_EXPORTER_OTLP_ENDPOINT is set AND the
  opentelemetry packages are importable. Otherwise get_tracer() returns a no-op
  tracer whose spans do nothing. Missing libs, a missing endpoint, or any error
  during setup degrade silently to the no-op path — init_tracer() never raises.

This keeps the otel packages a soft dependency: the trainer image can ship them
to emit traces to a collector, but a checkout without them still runs.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any

_LOG_CONFIGURED = False
_TRACER: Any = None


def get_logger(name: str = "kinetics_trainer", rank: int | None = None) -> logging.Logger:
    """Return a logger with a one-time-configured root handler.

    The torchrun RANK is stamped into every line so per-worker output is
    distinguishable when all ranks log to the same stream. Level is LOG_LEVEL
    (default INFO).
    """
    global _LOG_CONFIGURED
    if not _LOG_CONFIGURED:
        r = rank if rank is not None else os.environ.get("RANK", "0")
        logging.basicConfig(
            level=os.environ.get("LOG_LEVEL", "INFO").upper(),
            format=f"%(asctime)s %(levelname)s [rank={r}] %(name)s: %(message)s",
        )
        _LOG_CONFIGURED = True
    return logging.getLogger(name)


class _NoopSpan:
    def set_attribute(self, *_a, **_k) -> None: ...
    def set_attributes(self, *_a, **_k) -> None: ...
    def set_status(self, *_a, **_k) -> None: ...
    def record_exception(self, *_a, **_k) -> None: ...
    def add_event(self, *_a, **_k) -> None: ...
    def end(self, *_a, **_k) -> None: ...


class _NoopTracer:
    @contextmanager
    def start_as_current_span(self, _name: str, *_a, **_k) -> Iterator[_NoopSpan]:
        yield _NoopSpan()


def init_tracer(
    service_name: str = "kinetics-trainer",
    resource_attributes: dict[str, Any] | None = None,
) -> Any:
    """Idempotently initialize and return the global tracer.

    Returns a real OTel tracer when OTEL_EXPORTER_OTLP_ENDPOINT is set and the
    SDK + OTLP/HTTP exporter import cleanly; otherwise a no-op tracer. Safe to
    call from every rank.

    The OTLP HTTP exporter reads OTEL_EXPORTER_OTLP_ENDPOINT (and the standard
    OTEL_* env vars) itself, so no endpoint is passed explicitly here.
    """
    global _TRACER
    if _TRACER is not None:
        return _TRACER

    if not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "").strip():
        _TRACER = _NoopTracer()
        return _TRACER

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        attrs: dict[str, Any] = {"service.name": service_name}
        attrs.update({k: v for k, v in (resource_attributes or {}).items() if v is not None})

        provider = TracerProvider(resource=Resource.create(attrs))
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(provider)
        _TRACER = trace.get_tracer(service_name)
    except Exception as exc:  # missing libs / bad config -> stay silent, no-op
        get_logger().warning("tracing disabled (otel setup failed: %s)", exc)
        _TRACER = _NoopTracer()
    return _TRACER


def get_tracer() -> Any:
    """Return the configured tracer (real or no-op).

    init_tracer() is called lazily so get_tracer() is always safe even if init
    wasn't run first.
    """
    return _TRACER if _TRACER is not None else init_tracer()


def shutdown_tracer() -> None:
    """Flush and shut down the tracer provider so buffered spans are exported.

    No-op when tracing isn't configured.
    """
    try:
        from opentelemetry import trace

        provider = trace.get_tracer_provider()
        shutdown = getattr(provider, "shutdown", None)
        if callable(shutdown):
            shutdown()
    except Exception:
        pass
