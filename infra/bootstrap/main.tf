# -------------------------------------------------------------------
# Bootstrap del estado remoto. Se corre UNA SOLA VEZ antes del primer
# `terraform init` del stack principal (../).
#
# Uso:
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var state_bucket=medbot-tfstate-<sufijo-unico>
#
# Despues de aplicar, copia el nombre del bucket al backend del stack principal
# (../backend.tf) y corre `terraform init` arriba.
#
# Mantiene su estado en LOCAL a proposito: no podemos guardar el estado del
# bucket de estado dentro del propio bucket de estado (huevo y gallina).
# -------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "medbot"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  type        = string
  description = "Nombre global unico para el bucket de estado (ej. medbot-tfstate-upao-2026)"
}

variable "lock_table" {
  type    = string
  default = "medbot-tflock"
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket
  force_destroy = false # el estado es critico: no borrar accidentalmente
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "Copialo a ../backend.tf como `bucket = ...`"
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}
