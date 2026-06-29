variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Entorno (dev, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Número de zonas de disponibilidad (mínimo 2 para alta disponibilidad)"
  type        = number
  default     = 2
}

variable "app_image_tag" {
  description = "Etiqueta de la imagen Docker de MedBot publicada en ECR"
  type        = string
  default     = "latest"

  validation {
    condition     = length(trim(var.app_image_tag)) > 0
    error_message = "Debe configurar app_image_tag con una etiqueta Docker valida."
  }
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "alert_email" {
  description = "Email que recibe las alertas de SNS"
  type        = string
  default     = "equipo@example.com" # TODO
}

variable "medlineplus_url" {
  description = "URL del archivo XML comprimido del catálogo de MedlinePlus"
  type        = string
  default     = "https://medlineplus.gov/xml/mplus_topics_compressed_2024.zip" # TODO: verificar URL vigente
}
