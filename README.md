# kinetics-pipeline — HyperPod-on-EKS training infra

Infrastructure for training a video action-recognition model (CNN-LSTM on
Kinetics, with transfer learning) on **SageMaker HyperPod orchestrated by EKS** , with **cost controls built in from day one**.

## Architecture

![Kinetics Pipeline architecture](docs/architecture.png)

## Layout

```
terraform/                  # Modular IaC for the whole platform
  modules/
    vpc/                    # VPC, subnets, single NAT (cost), Karpenter tags
    eks/                    # EKS control plane + CPU node group + HyperPod
                            #   training operator (EKS managed add-on)
    iam/                    # HyperPod exec role + Pod Identity roles (ACK, Karpenter)
    karpenter/              # SQS interruption queue + EventBridge rules (Spot-safe)
    storage/                # S3 (data/checkpoints w/ lifecycle) + FSx for Lustre
    hyperpod/               # SageMaker HyperPod cluster (EKS orchestrator)
    cost/                   # Budgets, anomaly detection, auto-stop Lambda
    addons/                 # Bootstrap only: ArgoCD + EKS Pod Identity associations
helm/
  training-job/             # HyperPodPyTorchJob chart: distributed, auto-resume
gitops/
  apps/                     # ArgoCD apps: Karpenter, ACK SageMaker, Prometheus,
                            #   DCGM, FSx CSI, job,
                            #   karpenter-nodepools
  karpenter/                # Karpenter NodePool + EC2NodeClass (Spot-first, CPU)
cue/
  schema.cue                # Strict schemas for every manifest kind this repo emits
scripts/
  validate-manifests.sh     # helm render + gitops -> cue vet (strict)
Makefile                    # make validate = tf validate + manifest validation
scripts/
  scale-gpus.sh             # Scale the GPU group up for a run / down to 0
```

## Provision

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit emails, region, budget
terraform init
terraform apply
aws eks update-kubeconfig --region <region> --name <cluster>   # from outputs
```

Terraform installs **only** ArgoCD plus the EKS Pod Identity associations.
Everything else — Karpenter, ACK SageMaker, Prometheus/Grafana, DCGM,
FSx CSI driver and the training job — is an ArgoCD Application under
`gitops/apps/`, reconciled automatically once `gitops_repo_url` is set. (The
HyperPod training operator is an EKS managed add-on in the `eks` module, not a
GitOps app.)

### Auth: EKS Pod Identity (not IRSA)

Controllers that need AWS permissions (Karpenter, ACK SageMaker) use **EKS Pod
Identity**, not IRSA. Terraform creates the IAM roles (trusted by
`pods.eks.amazonaws.com`) and an `aws_eks_pod_identity_association` mapping
`(namespace, serviceaccount) -> role`. The Helm charts create their own
ServiceAccounts with no annotations — nothing AWS-specific lives in git. The
`eks-pod-identity-agent` EKS addon (enabled in the `eks` module) injects
credentials at runtime.

> Before syncing, set deployment-specific values:
> - `gitops/apps/karpenter.yaml` → `settings.clusterName`
> - `gitops/apps/ack-sagemaker.yaml` → `aws.region`
> - `gitops/karpenter/ec2nodeclass.yaml` → `role` (the
>   `<project>-<env>-karpenter-node` role from `terraform output`) and the
>   `karpenter.sh/discovery` tag values (your cluster name).

## Running a training job (the cost-aware loop)

GPUs default to **scale-to-zero** (`gpu_instance_count = 0`). You pay nothing
for GPUs until you explicitly scale up:

```bash
# 1. Scale the HyperPod GPU group up for the run
CLUSTER=<cluster> ./scripts/scale-gpus.sh up 2

# 2. Launch the job (ArgoCD sync, or directly)
helm upgrade --install kinetics helm/training-job -n training --create-namespace

# 3. When done, scale back down (or let the auto-stop Lambda do it)
./scripts/scale-gpus.sh down
```

## Validation

```bash
make validate            # terraform fmt+validate AND strict manifest validation
make validate-manifests  # just the CUE pass (needs helm + cue installed)
```

`scripts/validate-manifests.sh` renders the Helm chart (default **and**
FSx-enabled) and vets every rendered document — plus all `gitops/` manifests —
against `cue/schema.cue#Resource`. An unknown field, wrong type, or missing
required key fails the build. `#Resource` is an authoritative disjunction of the
kinds this repo emits (HyperPodPyTorchJob, PV/PVC, ArgoCD Application, Karpenter
NodePool / EC2NodeClass) — adding a manifest of any other kind fails on purpose.

## Cost controls in this repo

| Control | Where | Effect |
|---|---|---|
| GPU scale-to-zero default | `hyperpod` module, `gpu_instance_count=0` | No idle-GPU spend |
| Auto-stop Lambda | `cost` module | Scales GPUs to 0 when GPU util is idle |
| Monthly budget + alerts (50/80/100%) | `cost` module | Hard ceiling, early warning |
| Cost anomaly detection | `cost` module | Catches runaway spend |
| Spot-safe checkpointing | `helm/training-job` | Interruptions cost minutes, not hours |
| Karpenter Spot + SQS interruption queue | `karpenter` module + NodePool | Cheapest utility capacity, graceful drain on reclaim |
| S3 lifecycle on checkpoints | `storage` module | Old checkpoints expire, don't pile up |
| Single NAT gateway | `vpc` module | Cheaper than per-AZ NAT |
| Mixed precision + torch.compile | training values | Fewer GPU-hours per run |
| Transfer learning (pretrained) | training values | Converges in a fraction of the steps |
| DCGM/Prometheus GPU util | `gitops/apps` (ArgoCD) | See under-utilized GPUs you're paying for |
| Karpenter scale-to-zero (CPU side) | `gitops/apps` (ArgoCD) | Utility nodes don't idle |

## Notes / verify before apply

- **Provider/chart/CRD versions are pinned but move fast.** Verify
  `aws_sagemaker_cluster` schema, ACK SageMaker chart version, Karpenter,
  HyperPod training operator CRD version, and FSx CSI version against current
  releases. In particular, confirm the `HyperPodPyTorchJob` schema
  (`spec.replicaSpecs`, `spec.runPolicy.jobMaxRetryCount`) and the operator's
  install method (EKS managed add-on vs Helm) for your operator release.
- **Karpenter + Pod Identity:** confirm your pinned Karpenter version supports
  EKS Pod Identity (recent versions do). If you also want Spot-interruption
  handling, add an SQS interruption queue + the matching IAM statements.
- `train.py` (referenced by the Helm chart) lives in your training image
  (`docker/`), not in this infra repo — it must implement `--resume` from the
  S3 checkpoint for Spot safety to work.
- Use **Spot** for the GPU instance group during experimentation once you've
  confirmed checkpoint/resume works end-to-end; keep On-Demand for the final
  reproducible run.
