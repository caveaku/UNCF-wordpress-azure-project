###############################################################################
# STEP 5 - Presentation layer (regional): Application Gateway WAF_v2
#          = zone-redundant Layer-7 load balancer in front of the VM Scale Set
###############################################################################
resource "azurerm_public_ip" "appgw" {
  name                = "pip-${local.name}-appgw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  tags                = local.tags
}

resource "azurerm_web_application_firewall_policy" "appgw" {
  name                = "wafpol-${local.name}-appgw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  # Lock the origin: only traffic that came through *our* Front Door profile
  custom_rules {
    name      = "AllowOnlyOurFrontDoor"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "X-Azure-FDID"
      }
      operator           = "Equal"
      negation_condition = true
      match_values       = [azurerm_cdn_frontdoor_profile.this.resource_guid]
    }
  }

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 64
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

resource "azurerm_application_gateway" "this" {
  name                = "agw-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  zones               = local.zones
  firewall_policy_id  = azurerm_web_application_firewall_policy.appgw.id
  tags                = local.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  # The gateway itself autoscales with traffic
  autoscale_configuration {
    min_capacity = var.appgw_min_capacity
    max_capacity = var.appgw_max_capacity
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "appgw-ipcfg"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port
    port = 80
  }

  # VMSS instances register themselves into this pool (see compute.tf)
  backend_address_pool {
    name = local.appgw_backend_pool
  }

  backend_http_settings {
    name                                = local.appgw_http_settings
    cookie_based_affinity               = "Disabled" # stateless web tier
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = local.appgw_probe
    pick_host_name_from_backend_address = false

    connection_draining {
      enabled           = true
      drain_timeout_sec = 60
    }
  }

  probe {
    name                = local.appgw_probe
    protocol            = "Http"
    host                = "localhost"
    path                = "/health.php"
    interval            = 15
    timeout             = 10
    unhealthy_threshold = 3

    match {
      status_code = ["200"]
    }
  }

  http_listener {
    name                           = local.appgw_listener
    frontend_ip_configuration_name = local.appgw_frontend_ip
    frontend_port_name             = local.appgw_frontend_port
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgw_rule
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.appgw_listener
    backend_address_pool_name  = local.appgw_backend_pool
    backend_http_settings_name = local.appgw_http_settings
  }

  depends_on = [azurerm_subnet_network_security_group_association.appgw]
}
