# -------------------------------------------------------------------
# Composición raíz: aquí se cablean los módulos entre sí.
# Cada módulo es independiente y recibe solo lo que necesita.
# -------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "medbot-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "medbot-app"
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Conservar solo las ultimas 10 imagenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "network" {
  source   = "./modules/network"
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count
}

module "security" {
  source        = "./modules/security"
  vpc_id        = module.network.vpc_id
  db_secret_arn = module.data.db_secret_arn
}

module "data" {
  source             = "./modules/data"
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.network.db_sg_id
  instance_class     = var.db_instance_class
}

module "compute" {
  source            = "./modules/compute"
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  alb_sg_id         = module.network.alb_sg_id
  app_sg_id         = module.network.app_sg_id
  app_image         = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
  app_instance_role = module.security.app_instance_profile
  min_size          = var.asg_min_size
  max_size          = var.asg_max_size
  db_secret_arn     = module.data.db_secret_arn
  waf_acl_arn       = module.security.waf_arn
}

module "ingestion" {
  source           = "./modules/ingestion"
  app_subnet_ids   = module.network.app_subnet_ids
  app_sg_id        = module.network.app_sg_id
  db_secret_arn    = module.data.db_secret_arn
  medlineplus_url  = var.medlineplus_url
  alerts_topic_arn = module.observability.alerts_topic_arn
}

module "observability" {
  source      = "./modules/observability"
  alert_email = var.alert_email
  asg_name    = module.compute.asg_name
  rds_id      = module.data.rds_identifier
}
