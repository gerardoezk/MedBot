# MedBot — Asistente Médico Virtual basado en MedlinePlus

MedBot es un asistente médico virtual orientado a responder consultas básicas de salud usando información verificada del catálogo de **MedlinePlus**. El objetivo del proyecto es desplegar una arquitectura en AWS mediante **Infraestructura como Código**, evitando configuraciones manuales y reduciendo costos innecesarios.

Este repositorio prioriza una arquitectura práctica y económica: la aplicación consulta una base local en PostgreSQL previamente alimentada con datos de MedlinePlus, en lugar de consultar internet en cada pregunta del usuario.

---

## 1. Objetivo del proyecto

El sistema busca permitir que un usuario realice consultas de salud, por ejemplo:

* diabetes
* presión alta
* dolor de cabeza
* asma
* anemia

La respuesta del bot se genera únicamente desde el catálogo cargado en la base de datos local. Cada resultado incluye título, resumen y fuente asociada.

Importante: MedBot no reemplaza la atención médica profesional. La aplicación muestra información educativa y referencial.

---

## 2. Arquitectura implementada en el repositorio

La arquitectura real del repositorio está basada en los siguientes componentes:

```text
Usuario
  ↓
Application Load Balancer público
  ↓
Auto Scaling Group con EC2 privadas
  ↓
Contenedor Docker con FastAPI
  ↓
Amazon RDS PostgreSQL
```

Además, el sistema incluye un flujo de ingesta para cargar el catálogo médico:

```text
EventBridge Scheduler
  ↓
Lambda de descarga
  ↓
Bucket S3 de ingesta
  ↓
Lambda de carga
  ↓
Amazon RDS PostgreSQL
```

---

## 3. Componentes principales

### 3.1. Aplicación MedBot

La aplicación está desarrollada con:

* Python
* FastAPI
* Uvicorn
* Psycopg2
* Docker

El endpoint principal es:

```text
/search?q=termino
```

La aplicación consulta la tabla `catalog` en PostgreSQL y usa búsqueda por coincidencia parcial y similitud textual.

También expone:

```text
/health
```

Este endpoint es usado por el Application Load Balancer para verificar que la aplicación esté funcionando.

---

### 3.2. Base de datos PostgreSQL

La base de datos usa Amazon RDS PostgreSQL.

Contiene la tabla principal:

```text
catalog
```

Campos principales:

* `title`
* `url`
* `summary`

También se usa una tabla temporal:

```text
catalog_staging
```

La carga se realiza primero en `catalog_staging` y luego se reemplaza el contenido de `catalog`, reduciendo el riesgo de dejar datos incompletos.

Se habilita la extensión:

```sql
pg_trgm
```

Esto permite búsquedas por similitud y tolerancia a errores de escritura.

---

### 3.3. Ingesta de MedlinePlus

La ingesta se divide en dos Lambdas:

#### Lambda de descarga

Descarga el archivo comprimido del catálogo de MedlinePlus y lo guarda en S3.

Ruta usada en S3:

```text
incoming/catalog.zip
```

#### Lambda de carga

Lee el archivo desde S3, detecta si viene como ZIP o XML, extrae el XML si es necesario, procesa los temas médicos y los carga en PostgreSQL.

La Lambda valida que el catálogo tenga una cantidad mínima razonable de temas antes de reemplazar la tabla principal.

---

### 3.4. Seguridad

El repositorio aplica las siguientes prácticas:

* Las credenciales de RDS se almacenan en AWS Secrets Manager.
* Las EC2 solo pueden leer el secreto específico de RDS.
* Las Lambdas de ingesta tienen permisos limitados para S3, Secrets Manager y SQS.
* Las subredes de aplicación y datos son privadas.
* No se usa NAT Gateway para reducir costos.
* Se agregan VPC Endpoints privados para S3, Secrets Manager y ECR.
* El acceso externo a la aplicación se realiza mediante Application Load Balancer.

---

### 3.5. Contenedores y ECR

La aplicación se ejecuta como contenedor Docker.

Terraform crea un repositorio de Amazon ECR:

```text
medbot-app
```

La EC2 descarga la imagen desde ECR usando endpoints privados y permisos IAM.

Para evitar depender de internet durante el arranque, se usa una AMI optimizada para ECS basada en Amazon Linux 2023, la cual ya incluye Docker.

---

### 3.6. Observabilidad

El proyecto incluye recursos de observabilidad con:

* CloudWatch Logs
* CloudWatch Metrics
* CloudWatch Alarms
* Amazon SNS

El objetivo es detectar errores, baja memoria disponible en RDS y problemas operativos relevantes.

---

## 4. Estructura del repositorio

```text
MedBot/
├── app/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── src/
│       └── main.py
├── db/
│   └── schema.sql
├── ingestion/
│   ├── download/
│   │   └── handler.py
│   ├── load/
│   │   └── handler.py
│   └── requirements.txt
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── compute/
│       ├── data/
│       ├── ingestion/
│       ├── network/
│       ├── observability/
│       └── security/
├── ansible/
├── .github/
│   └── workflows/
│       └── validar-proyecto.yml
└── README.md
```

---

## 5. Validación automática

El repositorio incluye un workflow de GitHub Actions:

```text
Validar proyecto MedBot
```

Este workflow valida:

* Sintaxis Python
* Instalación de dependencias
* Construcción de imagen Docker
* Formato Terraform
* Inicialización Terraform sin backend remoto
* Validación Terraform

---

## 6. Comandos útiles

Validar sintaxis Python:

```bash
python -m compileall app ingestion
```

Construir imagen Docker local:

```bash
docker build -t medbot-app:local app
```

Validar formato Terraform:

```bash
terraform fmt -check -recursive infra
```

Inicializar Terraform sin backend remoto:

```bash
cd infra
terraform init -backend=false
terraform validate
```

---

## 7. Costos considerados

Para reducir costos, esta arquitectura evita:

* NAT Gateway
* dominio personalizado obligatorio
* Route 53 obligatorio
* servidores públicos innecesarios

Se usan VPC Endpoints para mantener comunicación privada con servicios AWS necesarios.

Recursos que sí pueden generar costo:

* EC2
* Application Load Balancer
* RDS PostgreSQL
* VPC Interface Endpoints
* ECR
* S3
* CloudWatch
* Lambda

Para una presentación académica, no es obligatorio comprar dominio. La aplicación puede demostrarse usando el DNS del Application Load Balancer.

---

## 8. Estado actual del proyecto

El repositorio ya incluye:

* Backend FastAPI para búsqueda médica.
* Carga del catálogo MedlinePlus desde archivo ZIP o XML.
* Infraestructura definida con Terraform.
* RDS PostgreSQL.
* ASG con EC2 privadas.
* ALB público.
* ECR para imagen Docker.
* VPC Endpoints privados para S3, Secrets Manager y ECR.
* Validación automática con GitHub Actions.

Pendiente para una implementación productiva completa:

* Publicar la imagen Docker real en ECR.
* Ejecutar `terraform apply` en una cuenta AWS configurada.
* Verificar costos antes del despliegue.
* Ajustar dominio y HTTPS si el profesor lo exige.
* Actualizar el documento Word y el diagrama para que coincidan con esta arquitectura.
