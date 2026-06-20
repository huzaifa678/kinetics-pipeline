FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir build

WORKDIR /build
COPY pyproject.toml ./
COPY src/ ./src/

# 1) Build the kinetics_trainer wheel. 2) Resolve + download/build wheels for
# its runtime deps (incl. the [otel] extra) into the same wheelhouse. torch /
# torchvision are excluded by pyproject (the base image provides them).
RUN python -m build --wheel --outdir /wheels . \
    && pip wheel --no-cache-dir --wheel-dir /wheels ".[otel,etl]"

FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime AS runtime

# ffmpeg provides the codecs PyAV needs to decode Kinetics mp4 clips.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Install the trainer + deps purely from local wheels, then drop the wheelhouse.
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels "kinetics-trainer[otel,etl]" \
    && rm -rf /wheels

# torchrun entrypoint script (the package itself is installed via the wheel).
COPY train.py ./train.py
COPY inference/ ./inference/

ENV NCCL_DEBUG=INFO

# torchrun is the launcher; the HyperPodPyTorchJob overrides args at runtime.
ENTRYPOINT ["torchrun", "--nproc_per_node=1", "/workspace/train.py"]
