variable "name" {
  description = "Resource name prefix (e.g. kinetics-pipeline-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the DB subnet group + security group in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (unused for ingress — kept for parity/tagging)."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group (Multi-AZ needs >= 2 AZs)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach Postgres on 5432 (the EKS node SG — Backstage pods egress from there)."
  type        = list(string)
}

variable "db_name" {
  description = "Initial database name Backstage connects to (its plugins create per-plugin DBs under this user)."
  type        = string
  default     = "backstage"
}

variable "username" {
  description = "Master username. Backstage's PG client owns all plugin databases, so it needs CREATEDB — the master user has it."
  type        = string
  default     = "backstage"
}

variable "engine_version" {
  description = "Postgres major.minor. Backstage supports PG 13+. Pin a minor RDS currently offers (16.4 was removed); auto_minor_version_upgrade keeps it current after create."
  type        = string
  default     = "16.10"
}

variable "instance_class" {
  description = "RDS instance class. Backstage's catalog/scaffolder load is light — a burstable t4g is plenty for an internal portal."
  type        = string
  default     = "db.t4g.small"
}

variable "allocated_storage" {
  description = "GiB of gp3 storage. Backstage's Postgres footprint is small (catalog + techdocs metadata)."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Multi-AZ standby. Off by default (internal dev-portal, not a customer-data store); flip on for prod HA."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block accidental terraform destroy of the DB. On by default for prod."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on delete. Backstage's DB is reproducible (catalog re-ingests from git) so this is safe to leave true."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Automated backup retention window in days."
  type        = number
  default     = 7
}

variable "secret_name" {
  description = "Secrets Manager name for the connection secret. MUST match the kinetics-* pattern the External Secrets role is scoped to, so ESO can sync it into the cluster."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
