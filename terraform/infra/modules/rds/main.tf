# ---------------------------------------------------------------------------
# Postgres for Backstage. Backstage REQUIRES a real database in production
# (SQLite is dev-only) — it stores the catalog, scaffolder tasks, TechDocs
# metadata and auth sessions. This is the ONLY stateful store Backstage needs.
#
# The generated master password is written to Secrets Manager under a
# `kinetics-*` name so the existing External Secrets Operator role (scoped to
# `secret:kinetics-*`) can sync it into the cluster as `backstage-db` — no new
# IAM role, and no plaintext DB password in git or Helm values.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-backstage"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-backstage-db-"
  description = "Backstage Postgres - ingress 5432 from the EKS node SG only."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-backstage-db" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Postgres 5432 from EKS nodes (Backstage pods)."
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all egress (RDS replies)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# 32-char password: no punctuation Backstage's DSN / libpq would need URL-encoded.
resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-backstage-"
  family      = "postgres16"
  description = "Backstage Postgres - force TLS in transit."

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  # checkov:skip=CKV_AWS_157:Multi-AZ is a per-env toggle (var.multi_az) - the internal dev portal doesn't need HA by default.
  # checkov:skip=CKV_AWS_118:Enhanced Monitoring not warranted for a light internal-portal DB.
  # checkov:skip=CKV_AWS_353:Performance Insights not warranted for this workload.
  identifier     = "${var.name}-backstage"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true # aws/rds KMS key - the connection secret carries the credential, not this.

  db_name  = var.db_name
  username = var.username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  # IAM DB auth is off: Backstage authenticates with the libpq password from the
  # synced secret (no AWS SDK in the PG client path), so password auth is the fit.
  iam_database_authentication_enabled = false

  backup_retention_period   = var.backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-backstage-final"
  copy_tags_to_snapshot     = true
  apply_immediately         = true

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}

# Connection secret in the kinetics-* namespace so ESO's existing role can read it.
# Backstage's app-config reads host/port/user/password out of the synced k8s Secret.
resource "aws_secretsmanager_secret" "db" {
  # checkov:skip=CKV_AWS_149:Default aws/secretsmanager key is fine - ESO decrypt is ViaService-scoped, no CMK key-policy plumbing.
  # checkov:skip=CKV2_AWS_57:Backstage DB password rotation is manual/reproducible (catalog re-ingests); no rotation lambda.
  name        = var.secret_name
  description = "Backstage Postgres connection (host/port/user/password) - synced into the cluster by ESO."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.this.address
    port     = tostring(aws_db_instance.this.port)
    username = var.username
    password = random_password.master.result
    database = var.db_name
  })
}
