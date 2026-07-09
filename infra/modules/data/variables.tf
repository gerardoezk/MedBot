variable "private_subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }
variable "instance_class" { type = string }
variable "multi_az" {
  description = "Indica si RDS se despliega en Multi-AZ"
  type        = bool
}
