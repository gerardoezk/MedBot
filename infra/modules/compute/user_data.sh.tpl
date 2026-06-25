#!/bin/bash
# Arranque mínimo de la instancia. Ansible hace el grueso de la configuración,
# pero dejamos Docker corriendo el contenedor para que el ASG sea funcional
# incluso antes de que Ansible pase.
set -euo pipefail
dnf install -y docker
systemctl enable --now docker

# La credencial de la BD se lee de Secrets Manager en tiempo de arranque
# (la instancia tiene un rol IAM que se lo permite). NUNCA se hornea en la imagen.
# El secret viene como JSON; lo convertimos a KEY=value para docker --env-file.
umask 077
aws secretsmanager get-secret-value --secret-id "${db_secret_arn}" \
  --query SecretString --output text \
  | python3 -c 'import sys,json; [print(f"{k}={v}") for k,v in json.load(sys.stdin).items()]' \
  > /etc/medbot.env

docker run -d --restart always -p 8000:8000 \
  --env-file /etc/medbot.env \
  "${app_image}"
