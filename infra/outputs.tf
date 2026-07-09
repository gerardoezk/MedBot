output "alb_dns_name" {
  description = "DNS público del balanceador (apuntar Route 53 / CloudFront aquí)"
  value       = module.compute.alb_dns_name
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos"
  value       = module.data.rds_endpoint
  sensitive   = true
}

output "ingestion_bucket" {
  description = "Bucket S3 donde la Lambda de descarga deja el XML"
  value       = module.ingestion.bucket_name
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR de la aplicacion MedBot"
  value       = aws_ecr_repository.app.repository_url
}

output "app_image_uri" {
  description = "URI completa de la imagen Docker usada por EC2"
  value       = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
}
