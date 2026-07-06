variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix and tag on all resources."
  type        = string
  default     = "kinetics-pipeline"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod). Stamped into the resource name prefix the infra + runner layers consume."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. The single source of truth — the infra layer reads this back out via remote_state (vpc_cidr output) for its SG rules."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2
}
