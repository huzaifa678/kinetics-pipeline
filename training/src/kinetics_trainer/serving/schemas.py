"""Pydantic request/response schemas for the inference API."""

from __future__ import annotations

from pydantic import BaseModel, Field, model_validator


class PredictRequest(BaseModel):
    """One of ``clip`` or ``video_b64`` must be provided (exactly one)."""

    clip: list | None = Field(
        default=None,
        description="Nested list shaped (T, 3, H, W), already normalized.",
    )
    video_b64: str | None = Field(
        default=None,
        description="Base64-encoded mp4 bytes, decoded + preprocessed server-side.",
    )
    top_k: int = Field(default=5, ge=1, le=50, description="Number of classes to return.")

    @model_validator(mode="after")
    def _exactly_one_input(self) -> PredictRequest:
        if (self.clip is None) == (self.video_b64 is None):
            raise ValueError("provide exactly one of 'clip' or 'video_b64'")
        return self


class Prediction(BaseModel):
    """A single top-k entry."""

    label: str
    score: float


class PredictResponse(BaseModel):
    """Top-k predictions for one request."""

    predictions: list[Prediction]


class HealthResponse(BaseModel):
    """Liveness / readiness probe payload."""

    status: str
    model_loaded: bool
