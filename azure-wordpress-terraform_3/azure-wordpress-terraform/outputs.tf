output "website_url" {
  description = "Public URL of the WordPress site (Front Door endpoint)."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}"
}

output "wordpress_setup_url" {
  description = "Open this once after deployment to finish the WordPress install wizard."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}/wp-admin/install.php"
}

output "app_gateway_public_ip" {
  description = "Origin IP (only reachable from Azure Front Door)."
  value       = azurerm_public_ip.appgw.ip_address
}

output "mysql_fqdn" {
  value = azurerm_mysql_flexible_server.this.fqdn
}

output "key_vault_name" {
  description = "Holds the MySQL admin password and the VM SSH private key."
  value       = azurerm_key_vault.this.name
}

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "vmss_name" {
  value = azurerm_linux_virtual_machine_scale_set.wordpress.name
}

output "nat_outbound_ip" {
  description = "All outbound traffic from the web tier leaves from this IP (useful for allow-lists)."
  value       = azurerm_public_ip.nat.ip_address
}
