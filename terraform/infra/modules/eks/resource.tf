resource "aws_launch_template" "system" {
  name_prefix = "${var.name}-system-"

  image_id = data.aws_ami.al2023_eks.id

  user_data = base64encode(templatefile("${path.module}/bootstrap.tpl", {
    cluster_name     = module.eks.cluster_name
    cluster_endpoint = module.eks.cluster_endpoint
    cluster_ca       = module.eks.cluster_certificate_authority_data
    cidr             = module.eks.cluster_service_cidr
  }))

  # Enforce IMDSv2 (CKV_AWS_79). hop_limit 2 so the VPC-CNI pod (aws-node) can
  # still reach IMDS; workloads use Pod Identity/IRSA, not node creds. This
  # deliberately trades off CKV_AWS_341 (which wants hop_limit 1) — 1 breaks CNI.
  # checkov:skip=CKV_AWS_341:hop_limit must be 2 for the EKS VPC-CNI pod to reach IMDS; kept in favour of the CKV_AWS_79 IMDSv2 hardening.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.name}-system-node"
    }
  }
}