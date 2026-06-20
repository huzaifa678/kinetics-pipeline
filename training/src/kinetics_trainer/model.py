"""Models: CNN-LSTM (per-frame 2D CNN features -> temporal LSTM) and baselines.

The primary model is CNN-LSTM; transfer learning starts the CNN backbone from
ImageNet weights.
"""

from __future__ import annotations

from collections.abc import Callable

import torch
import torch.nn as nn
import torchvision.models as tvm

from .config import Config

_BACKBONES = {
    "resnet18": (tvm.resnet18, tvm.ResNet18_Weights.IMAGENET1K_V1, 512),
    "resnet34": (tvm.resnet34, tvm.ResNet34_Weights.IMAGENET1K_V1, 512),
    "resnet50": (tvm.resnet50, tvm.ResNet50_Weights.IMAGENET1K_V2, 2048),
}


class CNNEncoder(nn.Module):
    """Per-frame 2D CNN feature extractor (the transfer-learning backbone).

    Input  : (B, T, C, H, W)
    Output : (B, T, feat_dim)
    """

    def __init__(self, backbone: str = "resnet50", pretrained: bool = True) -> None:
        super().__init__()
        if backbone not in _BACKBONES:
            raise ValueError(f"unknown backbone {backbone!r}")
        ctor, weights, feat_dim = _BACKBONES[backbone]
        net = ctor(weights=weights if pretrained else None)
        net.fc = nn.Identity()  # use as a feature extractor
        self.backbone = net
        self.feat_dim = feat_dim
        self._frozen = False

    def set_trainable(self, trainable: bool) -> None:
        self._frozen = not trainable
        for p in self.backbone.parameters():
            p.requires_grad = trainable
        # When frozen, also put the backbone in eval mode so BatchNorm stops
        # updating its running stats (otherwise "frozen" weights still drift).
        if self._frozen:
            self.backbone.eval()

    def train(self, mode: bool = True) -> CNNEncoder:  # type: ignore[override]
        super().train(mode)
        if self._frozen:
            self.backbone.eval()  # keep BN frozen even when the parent is train()
        return self

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        b, t, c, h, w = x.shape
        feats = self.backbone(x.reshape(b * t, c, h, w))  # (B*T, feat_dim)
        return feats.reshape(b, t, self.feat_dim)  # (B, T, feat_dim)


class LSTMHead(nn.Module):
    """Temporal LSTM over per-frame features + classifier.

    Input  : (B, T, feat_dim)
    Output : (B, num_classes)
    """

    def __init__(
        self,
        feat_dim: int,
        num_classes: int,
        hidden_size: int = 512,
        lstm_layers: int = 2,
        bidirectional: bool = True,
        dropout: float = 0.3,
    ) -> None:
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=feat_dim,
            hidden_size=hidden_size,
            num_layers=lstm_layers,
            batch_first=True,
            bidirectional=bidirectional,
            dropout=dropout if lstm_layers > 1 else 0.0,
        )
        out_dim = hidden_size * (2 if bidirectional else 1)
        self.classifier = nn.Sequential(
            nn.LayerNorm(out_dim),
            nn.Dropout(dropout),
            nn.Linear(out_dim, num_classes),
        )

    def forward(self, feats: torch.Tensor) -> torch.Tensor:
        seq, _ = self.lstm(feats)  # (B, T, out_dim)
        pooled = seq.mean(dim=1)  # temporal average pooling
        return self.classifier(pooled)


class CNNLSTM(nn.Module):
    """Composes CNNEncoder (spatial) + LSTMHead (temporal)."""

    def __init__(
        self,
        num_classes: int,
        backbone: str = "resnet50",
        pretrained: bool = True,
        hidden_size: int = 512,
        lstm_layers: int = 2,
        bidirectional: bool = True,
        dropout: float = 0.3,
    ) -> None:
        super().__init__()
        self.encoder = CNNEncoder(backbone=backbone, pretrained=pretrained)
        self.temporal = LSTMHead(
            feat_dim=self.encoder.feat_dim,
            num_classes=num_classes,
            hidden_size=hidden_size,
            lstm_layers=lstm_layers,
            bidirectional=bidirectional,
            dropout=dropout,
        )

    @property
    def backbone(self) -> nn.Module:
        return self.encoder.backbone

    def set_backbone_trainable(self, trainable: bool) -> None:
        self.encoder.set_trainable(trainable)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.temporal(self.encoder(x))


ModelBuilder = Callable[[Config], nn.Module]
_MODEL_BUILDERS: dict[str, ModelBuilder] = {}


def register_model(name: str) -> Callable[[ModelBuilder], ModelBuilder]:
    def decorator(builder: ModelBuilder) -> ModelBuilder:
        _MODEL_BUILDERS[name] = builder
        return builder

    return decorator


class ModelFactory:
    """Resolves a Config to a model via the registry."""

    @classmethod
    def available(cls) -> list[str]:
        return sorted(_MODEL_BUILDERS)

    @classmethod
    def create(cls, cfg: Config) -> nn.Module:
        try:
            builder = _MODEL_BUILDERS[cfg.model]
        except KeyError:
            raise NotImplementedError(
                f"unknown model {cfg.model!r}; registered: {cls.available()}"
            ) from None
        return builder(cfg)


@register_model("cnn_lstm")
def _build_cnn_lstm(cfg: Config) -> nn.Module:
    return CNNLSTM(
        num_classes=cfg.num_classes,
        backbone=cfg.backbone,
        pretrained=cfg.pretrained,
        hidden_size=cfg.hidden_size,
        lstm_layers=cfg.lstm_layers,
        bidirectional=cfg.bidirectional,
    )


@register_model("r2plus1d")
def _build_r2plus1d(cfg: Config) -> nn.Module:
    # Optional 3D-CNN baseline (Kinetics-pretrained) for comparison.
    from torchvision.models.video import R2Plus1D_18_Weights, r2plus1d_18

    weights = R2Plus1D_18_Weights.KINETICS400_V1 if cfg.pretrained else None
    net = r2plus1d_18(weights=weights)
    net.fc = nn.Linear(net.fc.in_features, cfg.num_classes)
    return _ChannelsTimeAdapter(net)


# A heavier transformer challenger for A/B against the CNN-LSTM. Fine-tune from a
# pretrained checkpoint to keep GPU cost sane.
_VIDEOMAE_CHECKPOINT = "MCG-NJU/videomae-base"


@register_model("videomae")
def _build_videomae(cfg: Config) -> nn.Module:
    from transformers import VideoMAEForVideoClassification

    if cfg.pretrained:
        net = VideoMAEForVideoClassification.from_pretrained(
            _VIDEOMAE_CHECKPOINT,
            num_labels=cfg.num_classes,
            ignore_mismatched_sizes=True,
        )
    else:
        from transformers import VideoMAEConfig

        net = VideoMAEForVideoClassification(
            VideoMAEConfig(
                image_size=cfg.frame_size,
                num_frames=cfg.clip_length,
                num_labels=cfg.num_classes,
            )
        )
    return _VideoMAEAdapter(net)


def build_model(cfg: Config) -> nn.Module:
    """Backward-compatible thin wrapper over ModelFactory.create."""
    return ModelFactory.create(cfg)


class _ChannelsTimeAdapter(nn.Module):
    """Adapt (B, T, C, H, W) clips to the (B, C, T, H, W) layout 3D-CNNs expect.

    The dataloader yields clips as (B, T, C, H, W) — what CNN-LSTM expects — but
    torchvision's video 3D-CNNs want (B, C, T, H, W). Swap the T/C axes so the
    r2plus1d baseline consumes the exact same batch tensor.
    """

    def __init__(self, net: nn.Module) -> None:
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x.permute(0, 2, 1, 3, 4))


class _VideoMAEAdapter(nn.Module):
    """Adapt a HF VideoMAEForVideoClassification to the trainer's tensor contract.

    The dataloader's (B, T, C, H, W) layout already matches VideoMAE's expected
    ``pixel_values`` shape (no permute needed); this just unwraps the HF
    ModelOutput so the rest of the pipeline sees a plain (B, num_classes) logits
    tensor like every other model.
    """

    def __init__(self, net: nn.Module) -> None:
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(pixel_values=x).logits


def build_param_groups(model: nn.Module, base_lr: float, backbone_lr_mult: float) -> list[dict]:
    """Build discriminative-LR param groups: backbone trains slower than the head.

    Frozen params (requires_grad=False) are excluded automatically.
    """
    if hasattr(model, "encoder"):
        backbone_ids = {id(p) for p in model.encoder.backbone.parameters()}
        backbone = [p for p in model.parameters() if p.requires_grad and id(p) in backbone_ids]
        head = [p for p in model.parameters() if p.requires_grad and id(p) not in backbone_ids]
        groups = []
        if head:
            groups.append({"params": head, "lr": base_lr})
        if backbone:
            groups.append({"params": backbone, "lr": base_lr * backbone_lr_mult})
        return groups
    return [{"params": [p for p in model.parameters() if p.requires_grad], "lr": base_lr}]


def model_config(cfg: Config) -> dict:
    """Serializable description used to rebuild the model at inference time."""
    return {
        "model": cfg.model,
        "backbone": cfg.backbone,
        "num_classes": cfg.num_classes,
        "hidden_size": cfg.hidden_size,
        "lstm_layers": cfg.lstm_layers,
        "bidirectional": cfg.bidirectional,
        "clip_length": cfg.clip_length,
        "frame_size": cfg.frame_size,
    }
