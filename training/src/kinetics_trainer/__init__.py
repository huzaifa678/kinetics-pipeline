"""kinetics_trainer — modular PyTorch CNN-LSTM trainer for the Kinetics dataset.

Runs distributed (torchrun/DDP) on SageMaker HyperPod GPU nodes and checkpoints
to S3 so the HyperPod training operator can auto-resume after a fault.
"""

__version__ = "0.1.0"
