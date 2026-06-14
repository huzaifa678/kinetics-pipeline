"""Pure training utilities shared by the Trainer: the accuracy metric and AMP table.

The train/eval loops live on the Trainer (they're stateful and own
optimizer/scaler/checkpointing); these helpers are deliberately stateless so they
stay trivially testable.
"""

from __future__ import annotations

import torch

AMP_DTYPE = {"fp16": torch.float16, "bf16": torch.bfloat16}


@torch.no_grad()
def accuracy(
    logits: torch.Tensor, target: torch.Tensor, ks: tuple[int, ...] = (1, 5)
) -> dict[int, float]:
    """Summed top-k correct counts (not yet divided by N) for each k in ks."""
    maxk = min(max(ks), logits.size(1))
    _, pred = logits.topk(maxk, dim=1)
    pred = pred.t()
    correct = pred.eq(target.view(1, -1).expand_as(pred))
    out = {}
    for k in ks:
        kk = min(k, maxk)
        out[k] = correct[:kk].reshape(-1).float().sum().item()
    return out
