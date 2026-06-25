# MedBot — Infraestructura como Código

Buscador de temas de salud sobre el catálogo de MedlinePlus, desplegado en AWS
y definido íntegramente como código (Terraform + Ansible + GitHub Actions).

> **Esto es un esqueleto, no un sistema listo para `apply`.** Define la estructura,
> los módulos y el cableado entre componentes. Hay marcadores `# TODO` donde ustedes
> deben poner valores propios (IDs de cuenta, dominio, AMI, etc.). Léanlo de arriba
> hacia abajo antes de ejecutar nada.

## Qué hay aquí

| Carpeta | Contenido |
|---|---|
| `infra/` | Terraform: composición raíz + módulos (network, data, compute, ingestion, observability, security) |
| `app/` | API del buscador (FastAPI) + Dockerfile |
| `ingestion/` | Código de las dos Lambdas de ingesta (descarga + carga) |
| `ansible/` | Playbooks que configuran las EC2 (app y monitoreo) |
| `policy/` | Políticas OPA/Conftest que valida el pipeline |
| `db/` | Esquema SQL del catálogo (incluye `pg_trgm` y tablas staging) |
| `.github/workflows/` | Pipeline CI/CD |

## Arquitectura (resumen)

```
Usuarios -> Route 53 -> CloudFront + WAF -> S3 (frontend)
                                         -> ALB -> ASG (EC2 + contenedor app) -> RDS PostgreSQL Multi-AZ
Ingesta:  EventBridge -> Lambda descarga (fuera VPC) -> S3 -> Lambda carga (Gateway Endpoint, sin NAT) -> RDS
Observab: CloudWatch + SNS (base). Prometheus/Grafana/Loki = stretch via Ansible.
```

## Decisiones tomadas (cámbienlas si quieren)
- Cómputo: **EC2 + Auto Scaling Group** corriendo el contenedor (no serverless). Es lo que permite demostrar ASG, balanceo y Ansible.
- App: **Python / FastAPI**.
- Ingesta: **dos pasos** (descarga fuera de la VPC, carga dentro vía Gateway Endpoint de S3) para no pagar NAT.
- Observabilidad base: **CloudWatch + SNS**. Prometheus/Grafana/Loki quedan como rol de Ansible a completar.

## Orden de despliegue (alto nivel)
1. Crear el bucket de estado y la tabla de lock (ver `infra/backend.tf`). **Esto es manual la primera vez** (problema del huevo y la gallina del estado remoto).
2. `cp infra/terraform.tfvars.example infra/terraform.tfvars` y rellenar valores.
3. `cd infra && terraform init && terraform plan`.
4. Construir y subir la imagen de la app a ECR (lo hace el pipeline).
5. `terraform apply`.
6. Ansible configura las instancias (lo dispara el pipeline o se corre a mano).

## Lo que NO está resuelto y deben decidir
- AMI base del launch template (`# TODO` en `modules/compute`).
- Certificado ACM / dominio real para HTTPS.
- Reglas administradas concretas del WAF.
- El stack Prometheus/Grafana/Loki (rol `ansible/roles/monitoring` está vacío a propósito).
- Estrategia de despliegue de nueva versión del contenedor (rolling del ASG).

## Advertencia de costos
RDS Multi-AZ y las EC2 del ASG están **siempre encendidas**: esto cuesta aunque no haya tráfico.
Para la entrega, levántenlo para probar y **destrúyanlo después** (`terraform destroy`).
