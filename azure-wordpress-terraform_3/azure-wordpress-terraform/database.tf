###############################################################################
# STEP 7 - Database layer: Azure Database for MySQL Flexible Server
#          Zone-redundant HA (primary zone 1, hot standby zone 2), private only
###############################################################################
resource "azurerm_private_dns_zone" "mysql" {
  name                = "${local.name}-${local.suffix}.private.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "link-mysql-${local.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

resource "azurerm_mysql_flexible_server" "this" {
  name                         = "mysql-${local.name}-${local.suffix}"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  administrator_login          = var.mysql_admin_username
  administrator_password       = random_password.mysql_admin.result
  sku_name                     = var.mysql_sku
  version                      = var.mysql_version
  zone                         = "1"
  delegated_subnet_id          = azurerm_subnet.db.id
  private_dns_zone_id          = azurerm_private_dns_zone.mysql.id
  backup_retention_days        = 35
  geo_redundant_backup_enabled = true
  tags                         = local.tags

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  storage {
    size_gb            = var.mysql_storage_gb
    auto_grow_enabled  = true
    io_scaling_enabled = true
  }

  maintenance_window {
    day_of_week  = 0 # Sunday
    start_hour   = 4
    start_minute = 0
  }

  lifecycle {
    # After an automatic failover Azure swaps primary/standby zones - don't fight it
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.mysql,
    azurerm_subnet_network_security_group_association.db
  ]
}

resource "azurerm_mysql_flexible_database" "wordpress" {
  name                = "wordpress"
  resource_group_name = azurerm_resource_group.this.name
  server_name         = azurerm_mysql_flexible_server.this.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Tune for many concurrent PHP workers
resource "azurerm_mysql_flexible_server_configuration" "max_connections" {
  name                = "max_connections"
  resource_group_name = azurerm_resource_group.this.name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = "1500"
}
