# Ingesta automatica en dos pasos (sin NAT):
#  1) Lambda "descarga": corre FUERA de la VPC, baja el XML de MedlinePlus y lo deja en S3.
#  2) Lambda "carga": corre DENTRO de la VPC, lee de S3 por el Gateway Endpoint, valida,
#     hace carga atomica (staging -> swap) hacia RDS.
# Un EventBridge Scheduler dispara el paso 1 cada dia.

resource "aws_s3_bucket" "ingest" {
  bucket_prefix = "medbot-ingest-"
  force_destroy = true
}

# Cifrado en reposo (politica OPA lo exige). AWS provider 5.x requiere recurso aparte.
resource "aws_s3_bucket_server_side_encryption_configuration" "ingest" {
  bucket = aws_s3_bucket.ingest.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquea acceso publico al bucket de ingesta por defecto.
resource "aws_s3_bucket_public_access_block" "ingest" {
  bucket                  = aws_s3_bucket.ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cola de mensajes muertos: si la carga falla, el evento cae aqui y dispara alerta.
resource "aws_sqs_queue" "dlq" {
  name = "medbot-ingest-dlq"
}

# --- Empaquetado del codigo ---
# La Lambda de descarga solo usa boto3 (incluido en el runtime), zipear el .py basta.
data "archive_file" "download" {
  type        = "zip"
  source_dir  = "${path.root}/../ingestion/download"
  output_path = "${path.module}/build/download.zip"
}

# La Lambda de carga necesita psycopg2-binary. Lo instalamos en un dir de build
# y luego se zipea junto con el handler. Requiere `python` y `pip` en el host que
# corre terraform (CI Ubuntu lo tiene; en Windows usar WSL o git-bash con Python).
resource "null_resource" "load_build" {
  triggers = {
    handler      = filesha256("${path.root}/../ingestion/load/handler.py")
    requirements = filesha256("${path.root}/../ingestion/requirements.txt")
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      BUILD="${path.module}/build/load"
      rm -rf "$BUILD"
      mkdir -p "$BUILD"
      python -m pip install --quiet --target "$BUILD" -r "${path.root}/../ingestion/requirements.txt"
      cp "${path.root}/../ingestion/load/handler.py" "$BUILD/"
    EOT
  }
}

data "archive_file" "load" {
  type        = "zip"
  source_dir  = "${path.module}/build/load"
  output_path = "${path.module}/build/load.zip"
  depends_on  = [null_resource.load_build]
}

# --- Paso 1: descarga (fuera de la VPC, tiene internet gratis) ---
resource "aws_lambda_function" "download" {
  function_name    = "medbot-ingest-download"
  runtime          = "python3.12"
  handler          = "handler.main"
  filename         = data.archive_file.download.output_path
  source_code_hash = data.archive_file.download.output_base64sha256
  timeout          = 120
  role             = aws_iam_role.ingest.arn
  environment {
    variables = {
      SOURCE_URL = var.medlineplus_url
      BUCKET     = aws_s3_bucket.ingest.id
    }
  }
}

# --- Paso 2: carga (dentro de la VPC, llega a S3 por el Gateway Endpoint) ---
resource "aws_lambda_function" "load" {
  function_name    = "medbot-ingest-load"
  runtime          = "python3.12"
  handler          = "handler.main"
  filename         = data.archive_file.load.output_path
  source_code_hash = data.archive_file.load.output_base64sha256
  timeout          = 300
  role             = aws_iam_role.ingest.arn
  vpc_config {
    subnet_ids         = var.app_subnet_ids
    security_group_ids = [var.app_sg_id]
  }
  environment {
    variables = {
      BUCKET        = aws_s3_bucket.ingest.id
      DB_SECRET_ARN = var.db_secret_arn
    }
  }
  dead_letter_config { target_arn = aws_sqs_queue.dlq.arn }
}

# Cuando aparece un objeto nuevo en S3, dispara el paso 2.
resource "aws_s3_bucket_notification" "on_upload" {
  bucket = aws_s3_bucket.ingest.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.load.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.s3_invoke]
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.load.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ingest.arn
}

# --- Disparador programado del paso 1 ---
resource "aws_scheduler_schedule" "daily" {
  name = "medbot-ingest-daily"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "cron(0 7 * * ? *)" # 07:00 UTC cada dia
  target {
    arn      = aws_lambda_function.download.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# Alarma sobre la DLQ: si entra algo, avisa por SNS.
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "medbot-ingest-dlq-not-empty"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [var.alerts_topic_arn]
}

# --- IAM (resumido; afinar al minimo privilegio antes de prod) ---
resource "aws_iam_role" "ingest" {
  name = "medbot-ingest-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_basic" {
  role       = aws_iam_role.ingest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ingest_permissions" {
  name = "medbot-ingest-permissions"
  role = aws_iam_role.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LeerYEscribirCatalogoEnS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.ingest.arn}/incoming/*",
          "${aws_s3_bucket.ingest.arn}/_meta/*"
        ]
      },
      {
        Sid    = "LeerCredencialesDeBaseDeDatos"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.db_secret_arn
      },
      {
        Sid    = "EnviarErroresADLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

resource "aws_iam_role" "scheduler" {
  name = "medbot-scheduler-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke_download" {
  name = "medbot-scheduler-invoke-download"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvocarLambdaDeDescarga"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.download.arn
      }
    ]
  })
}

terraform {
  required_providers {
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
  }
}
