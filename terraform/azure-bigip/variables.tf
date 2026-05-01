variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "rg-bigip-eval"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Prefix for resource names; use alphanumeric characters only"
  type        = string
  default     = "bigipeval"
}

variable "vnet_cidr" {
  description = "VNet CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "mgmt_subnet_cidr" {
  description = "Management subnet CIDR"
  type        = string
  default     = "10.20.1.0/24"
}

variable "external_subnet_cidr" {
  description = "External subnet CIDR used for VIP traffic"
  type        = string
  default     = "10.20.2.0/24"
}

variable "allowed_cidr" {
  description = "Source CIDR allowed to reach BIG-IP management"
  type        = string
  default     = "0.0.0.0/0"
}

variable "bigip_vm_name" {
  description = "BIG-IP VM name"
  type        = string
  default     = "bigip-eval-01"
}

variable "bigip_hostname" {
  description = "BIG-IP hostname set by DO"
  type        = string
  default     = "bigip-eval-01.local"
}

variable "bigip_admin_username" {
  description = "BIG-IP admin username created by the F5 Azure module bootstrap"
  type        = string
  default     = "bigipuser"
}

variable "bigip_license_key" {
  description = "F5 BYOL or evaluation registration key"
  type        = string
  sensitive   = true
}

variable "bigip_instance_type" {
  description = "Azure VM size for BIG-IP"
  type        = string
  default     = "Standard_DS3_v2"
}

variable "bigip_publisher" {
  description = "Azure Marketplace publisher for BIG-IP"
  type        = string
  default     = "f5-networks"
}

variable "bigip_offer" {
  description = "Azure Marketplace offer for BIG-IP BYOL"
  type        = string
  default     = "f5-big-ip-byol"
}

variable "bigip_sku" {
  description = "Azure Marketplace SKU for BIG-IP BYOL"
  type        = string
  default     = "f5-big-ltm-2slot-byol"
}

variable "bigip_version" {
  description = "Azure Marketplace image version"
  type        = string
  default     = "latest"
}

variable "availability_zone" {
  description = "Availability zone passed to the F5 Azure module"
  type        = number
  default     = 1
}

variable "availability_zones_public_ip" {
  description = "Public IP zone setting; use No-Zone if the region does not support zone-redundant public IPs"
  type        = string
  default     = "No-Zone"
}

variable "bigip_mgmt_private_ip" {
  description = "Optional static management IP; leave empty for dynamic assignment"
  type        = string
  default     = ""
}

variable "bigip_external_self_ip" {
  description = "Primary external self IP configured on BIG-IP"
  type        = string
  default     = "10.20.2.10"
}

variable "vip1_private_ip" {
  description = "Private IP address for the first HTTPS VIP"
  type        = string
  default     = "10.20.2.11"
}

variable "vip2_private_ip" {
  description = "Private IP address for the second HTTPS VIP"
  type        = string
  default     = "10.20.2.12"
}

variable "f5_ssh_publickey" {
  description = "Required by the upstream F5 module even when SSH key auth is disabled; leave empty when enable_ssh_key is false"
  type        = string
  default     = ""
}

variable "zone_name" {
  description = "DNS zone used for VIP hostnames"
  type        = string
}

variable "vip1_hostname" {
  description = "Hostname for the first HTTPS VIP"
  type        = string
  default     = "vip1"
}

variable "vip2_hostname" {
  description = "Hostname for the second HTTPS VIP"
  type        = string
  default     = "vip2"
}

variable "acme_contact_email" {
  description = "Contact email used for the Let's Encrypt ACME account"
  type        = string
  default     = "admin@example.com"
}

variable "acme_directory_url" {
  description = "ACME directory URL used by kojot-acme"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_schedule" {
  description = "Cron schedule for automated certificate renewal checks"
  type        = string
  default     = "17 3 * * *"
}

variable "dns_servers" {
  description = "DNS servers configured by DO"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "ntp_servers" {
  description = "NTP servers configured by DO"
  type        = list(string)
  default     = ["0.pool.ntp.org", "1.pool.ntp.org"]
}

variable "provision_modules" {
  description = "BIG-IP module provisioning levels applied by DO"
  type        = map(string)
  default = {
    ltm = "nominal"
  }
}

variable "tags" {
  description = "Tags to apply to Azure resources"
  type        = map(string)
  default = {
    workload = "bigip-eval"
    managed  = "terraform"
  }
}
