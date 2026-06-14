#!/usr/bin/env python
"""Container entrypoint for the HyperPodPyTorchJob.

The job runs::

    torchrun --nproc_per_node=N /workspace/train.py [flags]

In the image the kinetics_trainer package is pip-installed (from a wheel), so
the import resolves directly. The fallback puts ./src on sys.path so a local
checkout runs without an install step too (`python train.py ...`).
"""

try:
    from kinetics_trainer.cli import main
except ModuleNotFoundError:  # local checkout, package not installed
    import os
    import sys

    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src"))
    from kinetics_trainer.cli import main

if __name__ == "__main__":
    main()
