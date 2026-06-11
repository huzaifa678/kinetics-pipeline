variable "repository_name" {
  description = "ECR repository name for the training image."
  type        = string
  default     = "kinetics-training"
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. IMMUTABLE prevents overwriting a pushed SHA tag."
  type        = string
  default     = "IMMUTABLE"
}

variable "max_image_count" {
  description = "Max number of tagged images to retain before expiring the oldest."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
