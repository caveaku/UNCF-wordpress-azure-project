###############################################################################
# STEP 3 - Identity & secrets: managed identity, Key Vault, generated secrets
###############################################################################

# Identity the VMs use to read secrets from Key Vault (no passwords in code)
resource "azurerm_user_assigned_identity" "vmss" {
  name                = "id-${local.name}-vmss"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${var.prefix}${var.environment}${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true # restricted by network_acls below
  tags                          = local.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.admin_ip_ranges
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }
}

# Terraform runner can write secrets
resource "azurerm_role_assignment" "kv_deployer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# VMs can read secrets
resource "azurerm_role_assignment" "kv_vmss" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.vmss.principal_id
}

# RBAC takes a minute to propagate before secrets can be written
resource "time_sleep" "kv_rbac" {
  depends_on      = [azurerm_role_assignment.kv_deployer]
  create_duration = "90s"
}

# ---------------- Generated secrets ----------------
resource "random_password" "mysql_admin" {
  length           = 32
  special          = true
  override_special = "-_=+!#%*" # safe inside PHP strings and sed
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "tls_private_key" "vmss_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = random_password.mysql_admin.result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "password"
  depends_on   = [time_sleep.kv_rbac]
}

resource "azurerm_key_vault_secret" "vmss_ssh_private_key" {
  name         = "vmss-ssh-private-key"
  value        = tls_private_key.vmss_ssh.private_key_pem
  key_vault_id = azurerm_key_vault.this.id
  content_type = "ssh-private-key"
  depends_on   = [time_sleep.kv_rbac]
}
