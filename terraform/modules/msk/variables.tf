variable "name" {
  description = "Name prefix for all MSK resources (<project>-<environment>)."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the MSK security group in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR allowed to reach the brokers (intra-VPC only; no public access)."
  type        = string
}

variable "private_subnet_ids" {
  description = <<-EOT
    Private subnets for the broker ENIs — one per AZ. number_of_broker_nodes must
    be a multiple of the subnet count, so broker_count defaults to this length.
  EOT
  type        = list(string)
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Broker instance type. kafka.t3.small is the cost floor for dev."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_count" {
  description = <<-EOT
    Number of broker nodes. Must be a multiple of the number of client subnets
    (AZs). null = one broker per private subnet (the AZ count).
  EOT
  type        = number
  default     = null
}

variable "broker_ebs_volume_size" {
  description = "Per-broker EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
