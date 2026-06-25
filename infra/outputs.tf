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
