# Red: VPC con subredes públicas (ALB), privadas de app (ASG) y privadas de datos (RDS),
# repartidas en var.az_count zonas para alta disponibilidad (Semana 5 y 10).
# Clave de costos: usamos un GATEWAY ENDPOINT de S3 (gratis) en lugar de NAT Gateway.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "medbot-vpc" }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "medbot-default-sg-deny-all"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "medbot-igw" }
}

# --- Subredes (una de cada tipo por AZ) ---
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "medbot-public-${count.index}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "medbot-app-${count.index}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "medbot-data-${count.index}", Tier = "data" }
}

# --- Rutas ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "medbot-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Tabla privada SIN ruta a internet: las subredes de app/data no salen a internet.
# Lo poco que necesitan (S3) entra por el Gateway Endpoint de abajo.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "medbot-private-rt" }
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = var.az_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Gateway Endpoint de S3 (gratis, evita NAT) ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "medbot-s3-endpoint" }
}

# Interface Endpoint para Secrets Manager.
# Es necesario porque la Lambda de carga y las EC2 de la app están en subredes privadas
# y necesitan leer credenciales de RDS sin usar NAT Gateway.
resource "aws_security_group" "secretsmanager_endpoint" {
  name        = "medbot-secretsmanager-endpoint-sg"
  description = "Permite acceso privado a Secrets Manager desde la capa app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS desde EC2 app hacia endpoint privado de Secrets Manager"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "medbot-secretsmanager-endpoint-sg" }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "medbot-secretsmanager-endpoint" }
}

resource "aws_security_group" "ecr_endpoint" {
  name        = "medbot-ecr-endpoint-sg"
  description = "Permite acceso privado a ECR desde la capa app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS desde EC2 app hacia endpoints privados de ECR"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "medbot-ecr-endpoint-sg" }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.ecr_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "medbot-ecr-api-endpoint" }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.ecr_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "medbot-ecr-dkr-endpoint" }
}

resource "aws_security_group" "alb" {
  name        = "medbot-alb-sg"
  description = "Permite trafico publico HTTP/HTTPS hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS publico hacia el ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP publico hacia el ALB para demo academica sin dominio"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Trafico del ALB hacia la app FastAPI en subredes privadas"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "app" {
  name        = "medbot-app-sg"
  description = "Permite trafico del ALB hacia la app y salida limitada a servicios internos"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Trafico desde ALB hacia FastAPI"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Salida HTTPS hacia endpoints privados dentro de la VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Salida PostgreSQL hacia RDS dentro de la VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Salida HTTPS hacia S3 mediante Gateway Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }
}

resource "aws_security_group" "db" {
  name        = "medbot-db-sg"
  description = "Permite acceso PostgreSQL solo desde la capa app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL desde la capa app hacia RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}
