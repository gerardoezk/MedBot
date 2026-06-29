#!/bin/bash
# Arranque minimo de la instancia.
# La instancia ejecuta el contenedor de MedBot y obtiene las credenciales de RDS
# desde Secrets Manager.

set -euo pipefail

APP_IMAGE="${app_image}"
AWS_REGION="${region}"

if [ -z "$APP_IMAGE" ]; then
  echo "ERROR: app_image no fue configurado. Debe apuntar a una imagen Docker en ECR." >&2
  exit 1
fi

# La AMI optimizada para ECS ya incluye Docker.
# No instalamos paquetes desde internet porque la instancia está en subred privada sin NAT.
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker no está instalado en la AMI. Use una AMI optimizada para ECS." >&2
  exit 1
fi

systemctl enable --now docker

# La credencial de la BD se lee de Secrets Manager en tiempo de arranque.
# El secreto viene como JSON y lo convertimos a KEY=value para docker --env-file.
umask 077
aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "${db_secret_arn}" \
  --query SecretString \
  --output text \
  | python3 -c 'import sys,json; [print(f"{k}={v}") for k,v in json.loads(sys.stdin.read()).items()]' \
  > /etc/medbot.env

# Login privado a Amazon ECR.
ECR_REGISTRY="$(echo "$APP_IMAGE" | cut -d/ -f1)"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker pull "$APP_IMAGE"

docker rm -f medbot 2>/dev/null || true

docker run -d \
  --name medbot \
  --restart always \
  -p 8000:8000 \
  --env-file /etc/medbot.env \
  "$APP_IMAGE"