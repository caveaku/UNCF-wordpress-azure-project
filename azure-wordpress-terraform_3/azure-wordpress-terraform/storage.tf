###############################################################################
# STEP 6 - Data layer (files): Azure Files Premium NFS, zone-redundant
#          Holds WordPress core + wp-content (uploads, themes, plugins) so every
#          VM in the scale set serves exactly the same site.
###############################################################################
resource "azurerm_storage_account" "wp" {
  name                          = "st${var.prefix}${var.environment}${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  account_kind                  = "FileStorage"
  account_tier                  = "Premium"
  account_replication_type      = "ZRS" # survives a full zone outage
  https_traffic_only_enabled    = false # NFS 4.1 does not use HTTPS; traffic stays on the private endpoint
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
  tags                          = local.tags
}

resource "azurerm_storage_share" "wp" {
  name               = "wordpress"
  storage_account_id = azurerm_storage_account.wp.id
  quota              = var.wp_content_share_quota_gb
  enabled_protocol   = "NFS"
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "link-file-${local.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "file" {
  name                = "pe-${local.name}-files"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-files"
    private_connection_resource_id = azurerm_storage_account.wp.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "files-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.file.id]
  }
}
