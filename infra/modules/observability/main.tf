# Observabilidad base con servicios nativos (Semana 11).
# El stack Prometheus + Grafana + Loki es el "stretch" y se levanta con Ansible
# sobre una instancia de monitoreo (ver ansible/roles/monitoring).

resource "aws_sns_topic" "alerts" {
  name              = "medbot-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarma: CPU alta sostenida en el ASG.
resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "medbot-asg-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = var.asg_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Alarma: poca memoria libre en RDS (sintoma temprano de saturacion).
resource "aws_cloudwatch_metric_alarm" "rds_mem" {
  alarm_name          = "medbot-rds-low-memory"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = var.rds_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 104857600 # 100 MB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
