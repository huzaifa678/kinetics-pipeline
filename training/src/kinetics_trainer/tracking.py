"""Experiment tracking behind an abstraction (the ExperimentTracker seam).

The Trainer depends on this seam, not on MLflow (DIP). Two implementations:

* ``MLflowTracker`` — real MLflow. Works with SageMaker-managed MLflow (pass the
  tracking-server ARN as the URI; the sagemaker-mlflow plugin handles SigV4).
* ``NullTracker`` — no-op, used on non-main ranks and local runs without MLflow,
  so the loop never branches on "is tracking on".

``build_tracker`` is the factory that picks one from config + rank.
"""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

from .config import Config


@runtime_checkable
class ExperimentTracker(Protocol):
    """The surface the training loop calls. Both backends honor this exactly."""

    enabled: bool

    def log_params(self, params: dict[str, Any]) -> None: ...

    def set_tags(self, tags: dict[str, Any]) -> None: ...

    def log_metrics(self, metrics: dict[str, float], step: int) -> None: ...

    def log_artifact(self, path: str) -> None: ...

    def end(self, status: str = "FINISHED") -> None: ...


class NullTracker:
    """No-op tracker — every call is a silent no-op."""

    enabled = False

    def log_params(self, params: dict[str, Any]) -> None:
        return None

    def set_tags(self, tags: dict[str, Any]) -> None:
        return None

    def log_metrics(self, metrics: dict[str, float], step: int) -> None:
        return None

    def log_artifact(self, path: str) -> None:
        return None

    def end(self, status: str = "FINISHED") -> None:
        return None


class MLflowTracker:
    """MLflow-backed tracker.

    Self-disables (no-op) if no URI is given or it's not the main process, so it's
    safe to construct directly as well as via the factory.
    """

    def __init__(self, uri: str, experiment: str, run_name: str, enabled: bool = True) -> None:
        self.enabled = bool(uri) and enabled
        self._mlflow = None
        if not self.enabled:
            return
        import mlflow

        self._mlflow = mlflow
        mlflow.set_tracking_uri(uri)
        mlflow.set_experiment(experiment)
        mlflow.start_run(run_name=run_name or None)

    def log_params(self, params: dict[str, Any]) -> None:
        if self.enabled:
            self._mlflow.log_params({k: str(v) for k, v in params.items()})

    def set_tags(self, tags: dict[str, Any]) -> None:
        if self.enabled:
            self._mlflow.set_tags(tags)

    def log_metrics(self, metrics: dict[str, float], step: int) -> None:
        if self.enabled:
            self._mlflow.log_metrics(metrics, step=step)

    def log_artifact(self, path: str) -> None:
        if self.enabled:
            self._mlflow.log_artifact(path)

    def end(self, status: str = "FINISHED") -> None:
        if self.enabled:
            self._mlflow.end_run(status=status)


# Backward-compatible alias (the class was previously named Tracker).
Tracker = MLflowTracker


def build_tracker(cfg: Config, enabled: bool) -> ExperimentTracker:
    """Pick a tracker from config + rank.

    Returns a real MLflowTracker only when a URI is configured AND this is the main
    rank; otherwise a NullTracker. Centralizes the enable decision so call sites
    just use the returned object.
    """
    if not (enabled and cfg.mlflow_tracking_uri):
        return NullTracker()
    return MLflowTracker(
        cfg.mlflow_tracking_uri, cfg.experiment_name, cfg.run_name, enabled=enabled
    )
