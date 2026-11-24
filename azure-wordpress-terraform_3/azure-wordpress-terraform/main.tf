###############################################################################
# STEP 1 - Foundation: naming, resource group, monitoring workspace
###############################################################################
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  name   = "${var.prefix}-${var.environment}"
  suffix = random_string.suffix.result
  zones  = ["1", "2", "3"]
  tags   = merge(var.tags, { environment = var.environment })

  # Names used inside the Application Gateway definition
  appgw_frontend_ip   = "appgw-fe-public"
  appgw_frontend_port = "port-80"
  appgw_backend_pool  = "pool-wordpress-vmss"
  appgw_http_settings = "settings-http-80"
  appgw_listener      = "listener-http"
  appgw_probe         = "probe-health"
  appgw_rule          = "rule-wordpress"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}-wordpress"
  location = var.location
  tags     = local.tags
}

# Central log store for App Gateway, Front Door, MySQL, VMSS diagnostics
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.tags
}
