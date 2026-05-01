output "bigip_management_ip" {
  description = "BIG-IP management public IP"
  value       = local.bigip_mgmt_ip
}

output "bigip_management_url" {
  description = "BIG-IP management URL"
  value       = "https://${local.bigip_mgmt_ip}:${local.bigip_mgmt_port}"
}

output "bigip_admin_username" {
  description = "BIG-IP admin username"
  value       = var.bigip_admin_username
}

output "bigip_admin_password" {
  description = "Generated BIG-IP admin password"
  value       = local.bigip_password
  sensitive   = true
}

output "do_declaration_file" {
  description = "Rendered Declarative Onboarding JSON file"
  value       = local_file.do_declaration.filename
}

output "bigip_do_info_url" {
  description = "BIG-IP Declarative Onboarding info endpoint"
  value       = "https://${local.bigip_mgmt_ip}:${local.bigip_mgmt_port}/mgmt/shared/declarative-onboarding/info"
}

output "bigip_do_tasks_url" {
  description = "BIG-IP Declarative Onboarding tasks endpoint"
  value       = "https://${local.bigip_mgmt_ip}:${local.bigip_mgmt_port}/mgmt/shared/declarative-onboarding/task"
}

output "vip1_public_ip" {
  description = "Public IP address for the first HTTPS VIP"
  value       = local.vip1_public_ip
}

output "vip2_public_ip" {
  description = "Public IP address for the second HTTPS VIP"
  value       = local.vip2_public_ip
}

output "vip1_url" {
  description = "Public URL for the first HTTPS VIP"
  value       = "https://${var.vip1_hostname}.${var.zone_name}"
}

output "vip2_url" {
  description = "Public URL for the second HTTPS VIP"
  value       = "https://${var.vip2_hostname}.${var.zone_name}"
}
