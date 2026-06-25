variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "app_sg_id" { type = string }
variable "app_image" { type = string }
variable "app_instance_role" { type = string }
variable "min_size" { type = number }
variable "max_size" { type = number }
variable "db_secret_arn" { type = string }
variable "waf_acl_arn" {
  type        = string
  description = "ARN del WAF v2 a asociar al ALB"
}
