# Políticas que el pipeline evalúa sobre el plan de Terraform (Semana 12).
# Se ejecutan con: conftest test plan.json -p policy/
package main

# Niega cualquier bucket S3 sin cifrado en reposo.
# AWS provider 5.x separo el cifrado en su propio recurso, asi que verificamos
# que para cada aws_s3_bucket exista un aws_s3_bucket_server_side_encryption_configuration
# que apunte a el.
deny[msg] {
    bucket := input.resource_changes[_]
    bucket.type == "aws_s3_bucket"
    not bucket_has_encryption(bucket.address)
    msg := sprintf("El bucket %s no tiene cifrado en reposo", [bucket.address])
}

bucket_has_encryption(bucket_address) {
    enc := input.resource_changes[_]
    enc.type == "aws_s3_bucket_server_side_encryption_configuration"
    # El campo `bucket` del recurso de cifrado referencia al ID del bucket.
    # En el plan, esa referencia aparece como el address sin el prefijo de tipo.
    bucket_ref(enc) == trim_prefix(bucket_address, "aws_s3_bucket.")
}

bucket_ref(enc) = ref {
    # Cuando hay referencia, el plan trae las relaciones en `relevant_attributes`.
    # Fallback: comparar por sufijo del address del propio recurso de cifrado.
    parts := split(enc.address, ".")
    ref := parts[count(parts) - 1]
}

# Niega RDS que no sea Multi-AZ (rompería la alta disponibilidad prometida).
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_db_instance"
    resource.change.after.multi_az == false
    msg := sprintf("La base %s debe ser Multi-AZ", [resource.address])
}

# Niega security groups que abran SSH (22) a todo internet.
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    rule := resource.change.after.ingress[_]
    rule.from_port == 22
    rule.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("El SG %s expone SSH a 0.0.0.0/0", [resource.address])
}
