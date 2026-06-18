"""MLServer custom runtime serving the CNN-LSTM via the shared Predictor core.

Packaged into a custom MLServer image (``Dockerfile.seldon``) and run as a Seldon
Core v2 ``Model`` on a custom ``Server``. This decouples the model forward-pass
(here) from the FastAPI edge: Seldon can version + A/B models while the edge rolls
out independently. The model logic itself is **not** duplicated — this runtime is
a thin V2-protocol adapter over :class:`kinetics_trainer.predictor.Predictor`, the
same core the FastAPI app and the SageMaker handler use.

I/O (Open Inference / V2 protocol)
----------------------------------
* input  ``clip`` — FP32 tensor, shape ``(T,3,H,W)`` or ``(B,T,3,H,W)``, already
  decoded + normalized by the edge.
* param  ``top_k`` — optional int (default 5), via request parameters.
* output ``predictions`` — JSON string ``[{"label": ..., "score": ...}, ...]``.

The artifact directory (``model.pth`` + ``model_config.json`` + ``label_map.json``)
is staged by Seldon's storage initializer at ``settings.parameters.uri``.
"""

from __future__ import annotations

import json

import numpy as np
import torch
from mlserver import MLModel
from mlserver.codecs import NumpyRequestCodec, StringCodec
from mlserver.types import InferenceRequest, InferenceResponse

from ..observability import get_logger
from ..predictor import Predictor

log = get_logger("kinetics_seldon_runtime")

DEFAULT_TOP_K = 5


class KineticsRuntime(MLModel):
    """Serves CNN-LSTM top-k action predictions over the V2 inference protocol."""

    async def load(self) -> bool:
        """Load the shared Predictor from the Seldon-staged artifact directory."""
        params = self.settings.parameters
        if params is None or not params.uri:
            raise ValueError("model settings must provide parameters.uri (artifact dir)")
        self._predictor = Predictor.from_model_dir(params.uri)
        log.info("KineticsRuntime loaded %d classes", self._predictor.num_classes)
        return True

    async def predict(self, payload: InferenceRequest) -> InferenceResponse:
        """Decode the clip tensor, run the model, return top-k as a JSON output."""
        arr = np.asarray(NumpyRequestCodec.decode_request(payload), dtype=np.float32)
        clip = torch.from_numpy(arr)
        preds = self._predictor.predict(clip, top_k=self._top_k(payload))
        body = json.dumps([{"label": p.label, "score": p.score} for p in preds])
        return InferenceResponse(
            model_name=self.name,
            outputs=[StringCodec.encode_output(name="predictions", payload=[body])],
        )

    @staticmethod
    def _top_k(payload: InferenceRequest) -> int:
        """Read top_k from request parameters, falling back to the default."""
        params = payload.parameters
        top_k = getattr(params, "top_k", None) if params is not None else None
        return int(top_k) if top_k is not None else DEFAULT_TOP_K
