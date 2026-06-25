# Estado remoto en S3 con bloqueo en DynamoDB (Semana 3 y 6 del sílabo).
#
# Antes del PRIMER `terraform init` de este stack:
#   1. cd bootstrap
#   2. terraform init
#   3. terraform apply -var state_bucket=<nombre-global-unico>
#   4. Copia el nombre del bucket al campo `bucket` de abajo.
#
# El sub-stack bootstrap mantiene su propio estado LOCAL para resolver el huevo
# y la gallina (no podemos guardar el estado del bucket en el bucket mismo).
terraform {
  backend "s3" {
    bucket         = "medbot-tfstate-CAMBIAR" # TODO: pegar la salida de bootstrap
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "medbot-tflock"
    encrypt        = true
  }
}
