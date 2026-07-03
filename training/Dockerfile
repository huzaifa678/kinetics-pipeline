FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential && rm -rf /var/lib/apt/lists/*

# Isolated venv that still sees the base image's torch/torchvision/CUDA stack.
RUN python -m venv --system-site-packages /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
COPY pyproject.toml ./
COPY src/ ./src/
RUN pip install ".[otel,etl]"

# --------------------------------------------------------------------------
FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime AS runtime

# PyAV (the mp4 decoder) ships ffmpeg in its wheel, so no system ffmpeg needed.
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    NCCL_DEBUG=INFO

COPY --from=builder /opt/venv /opt/venv

WORKDIR /workspace
# torchrun entrypoint script + inference helpers (the package is in the venv).
COPY train.py ./train.py
COPY inference/ ./inference/

# Run as a non-root user; GPU access does not require root.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /workspace
USER appuser

# torchrun is the launcher; the HyperPodPyTorchJob overrides args at runtime.
ENTRYPOINT ["torchrun", "--nproc_per_node=1", "/workspace/train.py"]
