resource "aws_launch_template" "system" {
  name_prefix = "${var.name}-system-"

  image_id = data.aws_ami.al2023_eks.id

  user_data = base64encode(templatefile("${path.module}/bootstrap.tpl", {
    cluster_name     = module.eks.cluster_name
    cluster_endpoint = module.eks.cluster_endpoint
    cluster_ca       = module.eks.cluster_certificate_authority_data
    cidr             = module.eks.cluster_service_cidr
  }))

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