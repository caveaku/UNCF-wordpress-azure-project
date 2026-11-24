###############################################################################
# STEP 8 - Application layer: Linux VM Scale Set across 3 zones running
#          NGINX + PHP-FPM + WordPress, bootstrapped by cloud-init
###############################################################################
resource "azurerm_linux_virtual_machine_scale_set" "wordpress" {
  name                = "vmss-${local.name}-wp"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.vmss_sku
  instances           = var.vmss_min_instances
  zones               = local.zones
  zone_balance        = true
  overprovision       = false
  upgrade_mode        = "Rolling"
  admin_username      = var.admin_username
  tags                = local.tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vmss_ssh.public_key_openssh
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vmss.id]
  }

  network_interface {
    name                          = "nic-wp"
    primary                       = true
    accelerated_networking_enabled = true

    ip_configuration {
      name      = "ipcfg"
      primary   = true
      subnet_id = azurerm_subnet.app.id
      # This is the link between the load balancer and the scale set:
      application_gateway_backend_address_pool_ids = [
        "${azurerm_application_gateway.this.id}/backendAddressPools/${local.appgw_backend_pool}"
      ]
    }
  }

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    storage_account    = azurerm_storage_account.wp.name
    share_name         = azurerm_storage_share.wp.name
    key_vault_name     = azurerm_key_vault.this.name
    db_secret_name     = azurerm_key_vault_secret.mysql_admin_password.name
    identity_client_id = azurerm_user_assigned_identity.vmss.client_id
    db_host            = azurerm_mysql_flexible_server.this.fqdn
    db_name            = azurerm_mysql_flexible_database.wordpress.name
    db_user            = var.mysql_admin_username
    site_host          = azurerm_cdn_frontdoor_endpoint.this.host_name
    wp_version         = var.wordpress_version
  }))

  # Health signal used by rolling upgrades and automatic instance repair
  extension {
    name                       = "HealthExtension"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
    settings = jsonencode({
      protocol    = "http"
      port        = 80
      requestPath = "/health.php"
    })
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches              = "PT2M"
  }

  automatic_os_upgrade_policy {
    disable_automatic_rollback  = false
    enable_automatic_os_upgrade = true
  }

  boot_diagnostics {}

  lifecycle {
    ignore_changes = [instances] # the autoscaler owns the instance count
  }

  depends_on = [
    azurerm_role_assignment.kv_vmss,
    azurerm_private_endpoint.file,
    azurerm_subnet_nat_gateway_association.app,
    azurerm_subnet_network_security_group_association.app
  ]
}

###############################################################################
# STEP 9 - Auto scaling: add/remove VMs based on CPU
###############################################################################
resource "azurerm_monitor_autoscale_setting" "wordpress" {
  name                = "autoscale-${local.name}-wp"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.wordpress.id
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.vmss_min_instances
      minimum = var.vmss_min_instances
      maximum = var.vmss_max_instances
    }

    # Scale OUT fast: +3 VMs (one per zone) when avg CPU > 60% for 5 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.wordpress.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "3"
        cooldown  = "PT5M"
      }
    }

    # Scale IN slowly: -1 VM when avg CPU < 25% for 15 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.wordpress.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  notification {
    email {
      custom_emails = [var.alert_email]
    }
  }
}
