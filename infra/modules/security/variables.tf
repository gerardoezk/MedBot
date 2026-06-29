variable "vpc_id" {
  type = string
}

variable "db_secret_arn" {
  description = "ARN del secreto de Secrets Manager con las credenciales de RDS"
  type        = string
}