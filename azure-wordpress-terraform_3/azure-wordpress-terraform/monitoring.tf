###############################################################################
# STEP 10 - Monitoring & alerting
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "diag-appgw"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log { category_group = "allLogs" }
}

resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "diag-frontdoor"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log { category_group = "allLogs" }
}

resource "azurerm_monitor_diagnostic_setting" "mysql" {
  name                       = "diag-mysql"
  target_resource_id         = azurerm_mysql_flexible_server.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log { category_group = "allLogs" }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-keyvault"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log { category_group = "audit" }
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${local.name}-ops"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "wpops"
  tags                = local.tags

  email_receiver {
    name          = "ops-email"
    email_address = var.alert_email
  }
}

# A backend VM is failing health checks
resource "azurerm_monitor_metric_alert" "appgw_unhealthy" {
  name                = "alert-${local.name}-appgw-unhealthy-hosts"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_application_gateway.this.id]
  description         = "One or more WordPress VMs are unhealthy behind Application Gateway."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action { action_group_id = azurerm_monitor_action_group.ops.id }
}

# Origin is returning server errors
resource "azurerm_monitor_metric_alert" "appgw_5xx" {
  name                = "alert-${local.name}-appgw-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_application_gateway.this.id]
  description         = "Application Gateway is seeing backend 5xx responses."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "ResponseStatus"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100

    dimension {
      name     = "HttpStatusGroup"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action { action_group_id = azurerm_monitor_action_group.ops.id }
}

# Database is running hot
resource "azurerm_monitor_metric_alert" "mysql_cpu" {
  name                = "alert-${local.name}-mysql-cpu"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_mysql_flexible_server.this.id]
  description         = "MySQL CPU above 80% - consider scaling the SKU or adding a read replica."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action { action_group_id = azurerm_monitor_action_group.ops.id }
}

# Scale set is at max size and still busy
resource "azurerm_monitor_metric_alert" "vmss_cpu" {
  name                = "alert-${local.name}-vmss-cpu"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.wordpress.id]
  description         = "WordPress VMs sustained above 85% CPU - autoscale max may be too low."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action { action_group_id = azurerm_monitor_action_group.ops.id }
}
