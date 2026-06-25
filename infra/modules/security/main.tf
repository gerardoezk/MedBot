# Seguridad e identidad (Semana 12): rol de las instancias con minimo privilegio + WAF.

resource "aws_iam_role" "app_instance" {
  name = "medbot-app-instance-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# La instancia solo puede LEER la credencial de la BD, nada mas.
resource "aws_iam_role_policy" "read_secret" {
  name = "read-db-secret"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "*" # TODO: restringir al ARN concreto del secret
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "medbot-app-instance-profile"
  role = aws_iam_role.app_instance.name
}

# WAF: aqui SI se hace rate-limiting real por IP (lo que API Gateway NO hacia).
# La asociacion con el ALB se crea en el modulo compute (que es quien tiene el ALB),
# leyendo aws_wafv2_web_acl.main.arn via output.
resource "aws_wafv2_web_acl" "main" {
  name  = "medbot-waf"
  scope = "REGIONAL" # asociar al ALB
  default_action {
    allow {}
  }

  # 1) Rate limit por IP real (lo que API Gateway NO hacia en el diseño viejo).
  rule {
    name     = "rate-limit-por-ip"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000 # peticiones por IP en 5 min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # 2) Reglas administradas comunes (cubren CVEs conocidos, request smuggling, etc.).
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rules"
      sampled_requests_enabled   = true
    }
  }

  # 3) Reglas anti-SQL injection (la app habla con Postgres).
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "medbot-waf"
    sampled_requests_enabled   = true
  }
}
