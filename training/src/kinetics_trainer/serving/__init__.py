"""FastAPI inference serving surface for the CNN-LSTM action recognizer.

Optional subpackage: its third-party deps (fastapi, uvicorn, prometheus-client,
pydantic) ship in the ``serving`` extra and are imported only when this package
is loaded, so the trainer runtime never pulls them in.
"""
