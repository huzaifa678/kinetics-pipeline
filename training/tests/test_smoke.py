"""Fast CPU smoke tests — no data, no GPU. Run: python -m pytest training/tests
or just `python training/tests/test_smoke.py`."""

import os
import sys

import torch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from kinetics_trainer.checkpoint import (
    CheckpointManager,
    NullStorage,
)
from kinetics_trainer.config import parse_args, str2bool
from kinetics_trainer.distributed import (
    DistContext,
    all_reduce_mean,
    barrier,
    cleanup,
    distributed_context,
    get_rank,
    get_world_size,
    is_dist_avail_and_initialized,
    setup_distributed,
)
from kinetics_trainer.model import (
    CNNLSTM,
    ModelFactory,
    build_model,
    build_param_groups,
    model_config,
)
from kinetics_trainer.tracking import (
    NullTracker,
    Tracker,
    build_tracker,
)


def test_str2bool():
    assert str2bool("true") and str2bool("1") and not str2bool("false")


def test_config_parses_chart_flags():
    cfg = parse_args(
        [
            "--model=cnn_lstm",
            "--backbone=resnet18",
            "--pretrained=false",
            "--num-classes=10",
            "--clip-length=8",
            "--batch-size=2",
            "--train-manifest=/data/train.csv",
            "--val-manifest=/data/val.csv",
            "--amp=bf16",
            "--torch-compile=false",
            "--resume=true",
        ]
    )
    assert cfg.model == "cnn_lstm" and cfg.num_classes == 10
    assert cfg.pretrained is False and cfg.resume is True


def test_cnn_lstm_forward():
    model = CNNLSTM(
        num_classes=7,
        backbone="resnet18",
        pretrained=False,
        hidden_size=64,
        lstm_layers=1,
        bidirectional=True,
    ).eval()
    x = torch.randn(2, 4, 3, 64, 64)  # (B,T,C,H,W)
    with torch.no_grad():
        out = model(x)
    assert out.shape == (2, 7)


def test_freeze_toggle_and_build():
    cfg = parse_args(
        [
            "--model=cnn_lstm",
            "--backbone=resnet18",
            "--pretrained=false",
            "--num-classes=5",
            "--train-manifest=x",
            "--val-manifest=y",
        ]
    )
    model = build_model(cfg)
    model.set_backbone_trainable(False)
    assert all(not p.requires_grad for p in model.backbone.parameters())
    model.set_backbone_trainable(True)
    assert all(p.requires_grad for p in model.backbone.parameters())
    assert model_config(cfg)["backbone"] == "resnet18"


def test_bn_freeze_keeps_backbone_eval():
    import torch

    model = CNNLSTM(
        num_classes=3, backbone="resnet18", pretrained=False, hidden_size=16, lstm_layers=1
    )
    model.set_backbone_trainable(False)
    model.train()  # parent in train mode...
    # ...but the frozen backbone's BN must stay in eval mode
    bns = [m for m in model.encoder.backbone.modules() if isinstance(m, torch.nn.BatchNorm2d)]
    assert bns and all(not m.training for m in bns)
    model.set_backbone_trainable(True)
    model.train()
    assert all(m.training for m in bns)


def test_discriminative_param_groups():
    cfg = parse_args(
        [
            "--model=cnn_lstm",
            "--backbone=resnet18",
            "--pretrained=false",
            "--num-classes=4",
            "--train-manifest=x",
            "--val-manifest=y",
        ]
    )
    model = build_model(cfg)
    model.set_backbone_trainable(True)
    groups = build_param_groups(model, base_lr=1e-3, backbone_lr_mult=0.1)
    lrs = sorted(g["lr"] for g in groups)
    assert len(groups) == 2 and lrs == [1e-4, 1e-3]  # backbone slower than head
    # frozen backbone -> single head group
    model.set_backbone_trainable(False)
    assert len(build_param_groups(model, 1e-3, 0.1)) == 1


def test_tracker_disabled_is_noop():
    t = Tracker(uri="", experiment="x", run_name="", enabled=True)
    assert t.enabled is False
    t.log_params({"a": 1})
    t.log_metrics({"m": 0.5}, step=0)
    t.end()  # no-ops, no error


def test_model_factory_registry():
    # cnn_lstm + r2plus1d are registered; factory builds without an if/elif chain.
    assert {"cnn_lstm", "r2plus1d"}.issubset(set(ModelFactory.available()))
    cfg = parse_args(
        [
            "--model=cnn_lstm",
            "--backbone=resnet18",
            "--pretrained=false",
            "--num-classes=4",
            "--train-manifest=x",
            "--val-manifest=y",
        ]
    )
    assert isinstance(ModelFactory.create(cfg), CNNLSTM)
    # build_model is a thin backward-compatible wrapper over the factory
    assert isinstance(build_model(cfg), CNNLSTM)


def test_model_factory_unknown_raises():
    cfg = parse_args(
        ["--model=cnn_lstm", "--num-classes=2", "--train-manifest=x", "--val-manifest=y"]
    )
    object.__setattr__(cfg, "model", "does-not-exist")
    try:
        ModelFactory.create(cfg)
    except NotImplementedError as e:
        assert "does-not-exist" in str(e)
    else:
        raise AssertionError("expected NotImplementedError")


def test_build_tracker_returns_null_when_disabled():
    cfg = parse_args(
        ["--model=cnn_lstm", "--num-classes=2", "--train-manifest=x", "--val-manifest=y"]
    )  # no mlflow uri
    # disabled on non-main rank, or with no URI -> NullTracker
    assert isinstance(build_tracker(cfg, enabled=False), NullTracker)
    assert isinstance(build_tracker(cfg, enabled=True), NullTracker)
    nt = NullTracker()
    assert nt.enabled is False
    nt.log_params({"a": 1})
    nt.log_metrics({"m": 1.0}, step=0)
    nt.log_artifact("/nope")
    nt.set_tags({"t": 1})
    nt.end()  # all no-ops


def test_checkpoint_manager_roundtrip_local(tmp_path=None):
    import tempfile

    d = tmp_path if tmp_path is not None else tempfile.mkdtemp()
    d = str(d)
    cm = CheckpointManager(output_dir=d, s3_prefix="", storage=NullStorage(), is_main=True)
    assert cm.load_latest() is None  # nothing to resume from yet
    cm.save({"model": {"w": torch.tensor([1.0, 2.0])}, "epoch": 3})
    loaded = cm.load_latest()
    assert loaded is not None and loaded["epoch"] == 3
    assert torch.equal(loaded["model"]["w"], torch.tensor([1.0, 2.0]))


def test_checkpoint_manager_non_main_is_noop(tmp_path=None):
    import tempfile

    d = str(tmp_path if tmp_path is not None else tempfile.mkdtemp())
    cm = CheckpointManager(output_dir=d, storage=NullStorage(), is_main=False)
    cm.save({"epoch": 1})  # non-main rank writes nothing
    assert cm.load_latest() is None


def test_checkpoint_manager_uses_injected_storage(tmp_path=None):
    """DI seam: a fake RemoteStorage captures upload/download without S3/boto3."""
    import tempfile

    class FakeStorage:
        def __init__(self):
            self.uploaded = []
            self.downloaded = []

        def upload(self, local_path, uri):
            self.uploaded.append((local_path, uri))

        def download(self, uri, local_path):
            self.downloaded.append((uri, local_path))
            return False

    d = str(tmp_path if tmp_path is not None else tempfile.mkdtemp())
    fake = FakeStorage()
    cm = CheckpointManager(output_dir=d, s3_prefix="s3://bucket/run/", storage=fake, is_main=True)
    cm.save({"epoch": 0})
    assert fake.uploaded and fake.uploaded[0][1] == "s3://bucket/run/latest.pt"


def test_setup_distributed_single_process(monkeypatch=None):
    # No torchrun env -> single-process CPU context, no process group.
    for var in ("WORLD_SIZE", "RANK", "LOCAL_RANK"):
        os.environ.pop(var, None)
    ctx = setup_distributed()
    assert isinstance(ctx, DistContext)
    assert ctx.world_size == 1 and ctx.rank == 0 and ctx.local_rank == 0
    assert ctx.distributed is False
    assert ctx.is_main and ctx.is_local_main
    assert not is_dist_avail_and_initialized()
    assert get_rank() == 0 and get_world_size() == 1


def test_setup_distributed_reads_env():
    # WORLD_SIZE=1 stays non-distributed even with a higher RANK env set.
    os.environ.update({"WORLD_SIZE": "1", "RANK": "0", "LOCAL_RANK": "0"})
    ctx = setup_distributed()
    assert ctx.distributed is False
    # garbage env falls back to defaults instead of crashing
    os.environ["WORLD_SIZE"] = "not-an-int"
    assert setup_distributed().world_size == 1
    os.environ.pop("WORLD_SIZE", None)


def test_dist_collectives_are_noops_single_process():
    # barrier/cleanup must be safe to call uninitialized; all_reduce_mean returns
    # the value unchanged and does NOT mutate the caller's tensor.
    barrier()
    cleanup()  # no-ops, no error
    x = torch.tensor([2.0, 4.0])
    out = all_reduce_mean(x)
    assert torch.equal(out, torch.tensor([2.0, 4.0]))
    assert torch.equal(x, torch.tensor([2.0, 4.0]))  # input untouched


def test_distributed_context_yields_and_cleans_up():
    for var in ("WORLD_SIZE", "RANK", "LOCAL_RANK"):
        os.environ.pop(var, None)
    with distributed_context() as ctx:
        assert isinstance(ctx, DistContext) and ctx.is_main
    assert not is_dist_avail_and_initialized()  # cleanup ran


if __name__ == "__main__":
    test_str2bool()
    test_config_parses_chart_flags()
    test_cnn_lstm_forward()
    test_freeze_toggle_and_build()
    test_bn_freeze_keeps_backbone_eval()
    test_discriminative_param_groups()
    test_tracker_disabled_is_noop()
    test_model_factory_registry()
    test_model_factory_unknown_raises()
    test_build_tracker_returns_null_when_disabled()
    test_checkpoint_manager_roundtrip_local()
    test_checkpoint_manager_non_main_is_noop()
    test_checkpoint_manager_uses_injected_storage()
    test_setup_distributed_single_process()
    test_setup_distributed_reads_env()
    test_dist_collectives_are_noops_single_process()
    test_distributed_context_yields_and_cleans_up()
    print("✓ all smoke tests passed")
