variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "az_count" {
  description = "Number of AZs."
  type        = number
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
