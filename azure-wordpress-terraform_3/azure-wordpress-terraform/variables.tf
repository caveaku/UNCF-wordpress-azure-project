###############################################################################
# Input variables
###############################################################################
variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region. Must support Availability Zones and MySQL Flexible Server zone-redundant HA."
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Short name used in every resource name (lowercase letters/numbers)."
  type        = string
  default     = "wp"
}

variable "environment" {
  description = "Environment name (prod, stage, dev)."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    workload   = "wordpress"
    managed_by = "terraform"
  }
}

# ---------------- Network ----------------
variable "vnet_address_space" {
  type    = string
  default = "10.20.0.0/16"
}

variable "admin_ip_ranges" {
  description = "Public IPs/CIDRs of the machines running Terraform (needed to write Key Vault secrets). Example: [\"203.0.113.10/32\"]"
  type        = list(string)
}

# ---------------- Presentation layer ----------------
variable "appgw_min_capacity" {
  description = "Minimum Application Gateway instances (2+ for zone redundancy)."
  type        = number
  default     = 2
}

variable "appgw_max_capacity" {
  description = "Maximum Application Gateway instances."
  type        = number
  default     = 20
}

# ---------------- Application layer ----------------
variable "vmss_sku" {
  description = "VM size for WordPress web/app servers."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "vmss_min_instances" {
  description = "Minimum VM instances. 3 = one per availability zone."
  type        = number
  default     = 3
}

variable "vmss_max_instances" {
  description = "Maximum VM instances the autoscaler may add."
  type        = number
  default     = 30
}

variable "admin_username" {
  type    = string
  default = "wpadmin"
}

variable "wordpress_version" {
  description = "WordPress version to install, e.g. \"6.8.3\", or \"latest\"."
  type        = string
  default     = "latest"
}

# ---------------- Database layer ----------------
variable "mysql_sku" {
  description = "MySQL Flexible Server SKU (General Purpose or Business Critical; Burstable does not support HA)."
  type        = string
  default     = "GP_Standard_D4ds_v4"
}

variable "mysql_version" {
  type    = string
  default = "8.0.21"
}

variable "mysql_storage_gb" {
  type    = number
  default = 256
}

variable "mysql_admin_username" {
  type    = string
  default = "wpdbadmin"
}

# ---------------- Shared content ----------------
variable "wp_content_share_quota_gb" {
  description = "Premium NFS share size in GiB (minimum 100). Bigger = more IOPS/throughput."
  type        = number
  default     = 256
}

# ---------------- Operations ----------------
variable "enable_bastion" {
  description = "Deploy Azure Bastion for SSH to VMs without public IPs."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email that receives monitoring and autoscale alerts."
  type        = string
}
