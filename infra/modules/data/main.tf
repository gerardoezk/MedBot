# Datos: RDS PostgreSQL Multi-AZ (Semana 10, alta disponibilidad).
# La credencial vive en Secrets Manager, nunca en el código (Semana 12).

resource "aws_db_subnet_group" "this" {
  name       = "medbot-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "medbot-db-subnets" }
}

# Genera una contraseña aleatoria y la guarda en Secrets Manager.
resource "random_password" "db" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name = "medbot/db/credentials"
}

resource "aws_db_instance" "postgres" {
  identifier                 = "medbot-db"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = var.instance_class
  allocated_storage          = 20
  storage_encrypted          = true
  db_name                    = "medbot"
  username                   = "medbot_admin"
  password                   = random_password.db.result
  multi_az                   = var.multi_az
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [var.db_sg_id]
  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = true # OK para dev; en prod debe ser false
  deletion_protection        = false
  # performance_insights_enabled = true
}

# El secret se rellena DESPUES de crear RDS para incluir el endpoint (host/port).
# Asi la app y la Lambda de carga leen una sola fuente de verdad.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "medbot_admin"
    password = random_password.db.result
    dbname   = "medbot"
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
  })
}

terraform {
  required_providers {
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
