variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — used by the FSx Lustre security group (port 988)."
  type        = string
}

variable "private_subnet_id" {
  description = "Subnet for the FSx file system (keep same AZ as GPU nodes)."
  type        = string
}

variable "fsx_storage_capacity_gb" {
  description = "FSx for Lustre capacity in GiB."
  type        = number
}

variable "checkpoint_retention_days" {
  description = "Days before checkpoints expire."
  type        = number
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
