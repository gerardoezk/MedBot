output "rds_endpoint" { value = aws_db_instance.postgres.endpoint }
output "rds_identifier" { value = aws_db_instance.postgres.identifier }

# depends_on en el output fuerza a los consumidores (compute, ingestion) a esperar
# a que el secret tenga el host de RDS dentro. Sin esto, EC2 podria arrancar y leer
# un secret aun sin endpoint.
output "db_secret_arn" {
  value      = aws_secretsmanager_secret.db.arn
  depends_on = [aws_secretsmanager_secret_version.db]
}
