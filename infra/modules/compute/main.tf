# Cómputo: ALB publico + Auto Scaling Group de EC2 corriendo el contenedor (Semana 10).
# El ASG reparte instancias en las subredes de app de ambas AZ.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  # TODO: fijar una AMI concreta para reproducibilidad en vez de "most_recent".
}

# --- ALB ---
resource "aws_lb" "app" {
  name               = "medbot-alb"
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name        = "medbot-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Asocia el WAF (creado en el modulo security) al ALB.
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = var.waf_acl_arn
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  # TODO: en prod, redirigir 80 -> 443 y poner un listener 443 con certificado ACM.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- Launch template + ASG ---
resource "aws_launch_template" "app" {
  name_prefix   = "medbot-app-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.small"
  iam_instance_profile { name = var.app_instance_role }
  vpc_security_group_ids = [var.app_sg_id]
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    app_image     = var.app_image
    db_secret_arn = var.db_secret_arn
  }))
}

resource "aws_autoscaling_group" "app" {
  name                = "medbot-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.min_size
  vpc_zone_identifier = var.app_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "medbot-app"
    propagate_at_launch = true
  }
}

# Escala según el uso de CPU (Semana 10).
resource "aws_autoscaling_policy" "cpu" {
  name                   = "medbot-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
