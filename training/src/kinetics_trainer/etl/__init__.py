"""Offline ETL: decode + shard Kinetics clips into WebDataset tars.

Precomputes the expensive PyAV decode once (the per-epoch training bottleneck) and
packs frames into WebDataset shards, so training streams pre-decoded uint8 frames
instead of re-decoding mp4s every epoch. Augmentation stays at train time — shards
hold decoded frames, not augmented tensors.
"""
