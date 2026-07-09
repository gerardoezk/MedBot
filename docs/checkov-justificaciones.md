# Justificación de hallazgos Checkov pendientes — MedBot

## Resumen del escaneo

Durante la validación de seguridad con Checkov se redujeron los hallazgos de infraestructura de 65 fallas iniciales a 39 fallas pendientes.

Los hallazgos restantes no se corrigieron todos directamente porque varias reglas corresponden a configuraciones productivas que implican costos adicionales, dominio propio, certificados, KMS Customer Managed Keys, replicación cross-region, logs avanzados o complejidad no requerida para el alcance académico del proyecto.

El criterio aplicado fue el siguiente:

- Corregir hallazgos gratuitos o de bajo costo.
- Mantener decisiones de arquitectura orientadas a reducir costos.
- Documentar excepciones cuando la regla no aplica al alcance académico.
- No agregar servicios innecesarios solo para reducir el número de fallas del escáner.

---

## Hallazgos corregidos previamente

Se corrigieron hallazgos relacionados con:

- Inmutabilidad de etiquetas en ECR.
- Rechazo de headers inválidos en ALB.
- Uso obligatorio de IMDSv2 en EC2.
- Actualizaciones menores automáticas en RDS.
- Copia de tags a snapshots de RDS.
- Versionado en S3 de ingesta.
- Lifecycle del bucket de ingesta.
- Cifrado administrado en SQS.
- DLQ para Lambdas de ingesta.
- Límite de concurrencia para Lambdas.
- X-Ray en Lambdas.
- Descripciones y restricciones en Security Groups.
- Cifrado administrado en SNS.
- Restricción del default security group.
- Subredes públicas sin asignación automática de IP pública.

---

## Excepciones justificadas

### HTTPS en ALB y redirección HTTP a HTTPS

Checks relacionados:

- CKV_AWS_2
- CKV_AWS_103
- CKV2_AWS_20
- CKV_AWS_260

Justificación:

El proyecto no implementa HTTPS completo en el ALB porque requiere un dominio propio y un certificado ACM validado. Para una entrega académica, se mantiene HTTP en el ALB como mecanismo de demostración usando el DNS del balanceador. En una implementación productiva, se debe configurar un dominio, certificado ACM, listener HTTPS 443 y redirección automática desde HTTP 80 hacia HTTPS 443.

---

### KMS Customer Managed Keys

Checks relacionados:

- CKV_AWS_119
- CKV_AWS_136
- CKV_AWS_145
- CKV_AWS_149
- CKV_AWS_173
- CKV_AWS_297

Justificación:

El proyecto usa cifrado administrado por AWS o cifrado por defecto en varios servicios para reducir complejidad y costos. Checkov recomienda Customer Managed Keys para mayor control criptográfico, pero esto agrega administración y costo mensual por clave KMS. Para el alcance académico, se acepta el cifrado administrado por AWS. En producción, se recomienda crear claves KMS separadas para ECR, S3, Secrets Manager, Lambda, EventBridge Scheduler y DynamoDB.

---

### NAT Gateway y Lambda de descarga fuera de VPC

Check relacionado:

- CKV_AWS_117

Justificación:

La Lambda de descarga del catálogo de MedlinePlus se mantiene fuera de la VPC de forma intencional. Su función es descargar el archivo público de MedlinePlus y almacenarlo en S3. Si se colocara dentro de la VPC, se requeriría NAT Gateway para acceder a internet, lo cual incrementaría el costo mensual. La Lambda de carga sí se ejecuta dentro de la VPC porque necesita conectarse a RDS.

---

### Code Signing en Lambda

Check relacionado:

- CKV_AWS_272

Justificación:

La validación de firma de código en Lambda es una práctica recomendada para ambientes productivos o empresariales. Para el proyecto académico, se considera fuera de alcance porque requiere administrar perfiles de firma y proceso adicional de publicación. Se recomienda implementarlo en una versión productiva.

---

### Replicación cross-region en S3

Check relacionado:

- CKV_AWS_144

Justificación:

La replicación cross-region aumenta disponibilidad ante desastres regionales, pero genera duplicación de almacenamiento, tráfico entre regiones y mayor complejidad operativa. Para MedBot, el bucket de ingesta almacena archivos descargables desde MedlinePlus, por lo que la recuperación puede realizarse volviendo a cargar el catálogo. Por ello no se implementa replicación cross-region en el alcance académico.

---

### Logs avanzados de ALB, WAF, S3 y VPC

Checks relacionados:

- CKV_AWS_91
- CKV2_AWS_31
- CKV_AWS_18
- CKV2_AWS_11

Justificación:

Los logs avanzados son recomendables para producción, pero pueden generar costos adicionales de almacenamiento y retención en S3 o CloudWatch. El proyecto ya contempla observabilidad básica con CloudWatch, CloudWatch Alarms y SNS. Para producción, se recomienda habilitar access logs del ALB, logs del WAF, server access logging en S3 y VPC Flow Logs.

---

### Monitoreo avanzado de RDS

Checks relacionados:

- CKV_AWS_118
- CKV_AWS_353
- CKV_AWS_129
- CKV2_AWS_30

Justificación:

El proyecto ya habilita Multi-AZ, backups y métricas básicas. Enhanced Monitoring, Performance Insights y query logging aumentan la visibilidad operativa, pero pueden generar costos adicionales y mayor volumen de logs. Para el alcance académico se consideran opcionales. En producción deben habilitarse con una política de retención definida.

---

### Autenticación IAM y rotación automática de Secrets Manager

Checks relacionados:

- CKV_AWS_161
- CKV2_AWS_57

Justificación:

MedBot usa Secrets Manager para almacenar credenciales de RDS de forma segura. Checkov recomienda autenticación IAM en RDS y rotación automática de secretos. Estas mejoras son válidas para producción, pero agregan complejidad de implementación en la aplicación y en la administración del secreto. Para la entrega académica se mantiene autenticación con usuario/contraseña almacenada en Secrets Manager.

---

### Protección contra eliminación en ALB y RDS

Checks relacionados:

- CKV_AWS_150
- CKV_AWS_293

Justificación:

Deletion protection evita eliminaciones accidentales, pero puede dificultar destruir recursos después de una demostración académica y generar costos si el estudiante olvida desactivar recursos. Por eso se deja como recomendación para producción, no como requisito de la versión académica.

---

### Target group HTTP interno

Check relacionado:

- CKV_AWS_378

Justificación:

El tráfico externo debería protegerse con HTTPS en producción. Sin embargo, el target group interno entre ALB y EC2 usa HTTP porque el tráfico viaja dentro de la VPC y simplifica la operación académica. En producción se recomienda usar HTTPS de extremo a extremo si el modelo de seguridad lo exige.

---

### Falsos positivos por módulos Terraform

Check relacionado:

- CKV2_AWS_5

Justificación:

Checkov reporta que algunos Security Groups no están adjuntos, pero en este proyecto se usan a través de salidas de módulos y son consumidos por otros módulos como compute y data. Por tanto, se consideran falsos positivos derivados de la estructura modular de Terraform.

---

## Conclusión

El escaneo Checkov permitió mejorar la postura de seguridad del proyecto y evidenciar decisiones arquitectónicas. Las fallas restantes no se ignoran sin análisis; se clasifican como excepciones justificadas por costo, alcance académico o decisiones intencionales de diseño.

En una versión productiva, se recomienda implementar:

- Dominio y HTTPS con ACM.
- KMS Customer Managed Keys.
- Logs avanzados de ALB, WAF, S3 y VPC.
- Performance Insights y Enhanced Monitoring en RDS.
- Rotación automática de secretos.
- Lambda code signing.
- Replicación cross-region en S3.
- Deletion protection en recursos críticos.
