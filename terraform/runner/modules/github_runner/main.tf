# ===========================================================================
# Self-hosted GitHub Actions runner in the VPC. Its only job is to give the CI
# a network path to the VPN-locked EKS API: egress is the NAT gateway EIP, which
# is already allow-listed on the cluster's public endpoint. terraform-plan/apply
# run here (runs-on: [self-hosted, vpc]) and still assume the tf roles via OIDC.
# ===========================================================================

data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# PAT for runner registration. Created empty — set the value out-of-band so no
# credential is committed: aws secretsmanager put-secret-value --secret-id <arn>
# --secret-string <pat>. Needs the repo's runner-admin scope.
resource "aws_secretsmanager_secret" "runner_pat" {
  name        = "${var.name}-gha-runner-pat"
  description = "GitHub PAT (runner-admin) the self-hosted runner uses to fetch a registration token."
  tags        = var.tags
}

# --- IAM: instance profile (no AWS creds for TF itself — that's OIDC; this only
# reads the PAT secret + allows SSM management). ---
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = "${var.name}-gha-runner"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_pat" {
  statement {
    sid       = "ReadRunnerPat"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.runner_pat.arn]
  }
}

resource "aws_iam_role_policy" "read_pat" {
  name   = "${var.name}-gha-runner-read-pat"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.read_pat.json
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.name}-gha-runner"
  role = aws_iam_role.runner.name
}

# --- Network: egress-only (GitHub, STS, ECR, EKS). SSM handles shell access, so
# no ingress. ---
resource "aws_security_group" "runner" {
  name        = "${var.name}-gha-runner"
  description = "Self-hosted GHA runner - egress only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-gha-runner" })
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.runner.id
  description       = "All egress (GitHub, STS, ECR, EKS API)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Compute: single self-healing runner via an ASG. ---
resource "aws_launch_template" "runner" {
  name_prefix   = "${var.name}-gha-runner-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner.arn
  }

  vpc_security_group_ids = [aws_security_group.runner.id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    region         = data.aws_region.current.name
    pat_secret_arn = aws_secretsmanager_secret.runner_pat.arn
    github_owner   = var.github_owner
    github_repo    = var.github_repo
    runner_labels  = var.runner_labels
    runner_name    = "${var.name}-vpc"
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-gha-runner" })
  }
}

resource "aws_autoscaling_group" "runner" {
  name                = "${var.name}-gha-runner"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  # Replace the instance when the launch template (e.g. user-data) changes.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-gha-runner"
    propagate_at_launch = true
  }
}
