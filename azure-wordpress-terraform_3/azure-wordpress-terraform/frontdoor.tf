###############################################################################
# STEP 4 - Presentation layer (edge): Azure Front Door Premium = CDN + global
#          load balancing + WAF + DDoS absorption
###############################################################################
resource "azurerm_cdn_frontdoor_profile" "this" {
  name                     = "afd-${local.name}-${local.suffix}"
  resource_group_name      = azurerm_resource_group.this.name
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 60
  tags                     = local.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${local.name}-${local.suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = local.tags
}

# Origin group: where Front Door sends cache misses
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "og-appgw"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    protocol            = "Http"
    interval_in_seconds = 30
    path                = "/health.php"
    request_type        = "HEAD"
  }
}

# Origin = the Application Gateway public IP (add a second region here for multi-region DR)
resource "azurerm_cdn_frontdoor_origin" "appgw" {
  name                           = "origin-appgw-${var.location}"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                        = true
  host_name                      = azurerm_public_ip.appgw.ip_address
  origin_host_header             = azurerm_cdn_frontdoor_endpoint.this.host_name
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false
}

# ---------------- Caching rules (this is what makes 200k users cheap) ----------------
resource "azurerm_cdn_frontdoor_rule_set" "wordpress" {
  name                     = "wordpressrules"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
}

# 1) Never cache admin, login, REST API, cron, xmlrpc
resource "azurerm_cdn_frontdoor_rule" "bypass_admin" {
  name                      = "BypassAdmin"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.wordpress.id
  order                     = 1
  behavior_on_match         = "Stop"

  conditions {
    url_path_condition {
      operator     = "Contains"
      match_values = ["wp-admin", "wp-login.php", "wp-json", "wp-cron.php", "xmlrpc.php", "preview="]
      transforms   = ["Lowercase"]
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior = "Disabled"
    }
  }

  depends_on = [azurerm_cdn_frontdoor_origin_group.this, azurerm_cdn_frontdoor_origin.appgw]
}

# 2) Never cache for logged-in users / commenters
resource "azurerm_cdn_frontdoor_rule" "bypass_logged_in" {
  name                      = "BypassLoggedIn"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.wordpress.id
  order                     = 2
  behavior_on_match         = "Stop"

  conditions {
    request_header_condition {
      header_name  = "Cookie"
      operator     = "Contains"
      match_values = ["wordpress_logged_in", "wp-postpass", "comment_author"]
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior = "Disabled"
    }
  }

  depends_on = [azurerm_cdn_frontdoor_origin_group.this, azurerm_cdn_frontdoor_origin.appgw]
}

# 3) Static assets: cache 7 days at the edge
resource "azurerm_cdn_frontdoor_rule" "cache_static" {
  name                      = "CacheStatic"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.wordpress.id
  order                     = 3
  behavior_on_match         = "Continue"

  conditions {
    url_file_extension_condition {
      operator     = "Equal"
      match_values = ["css", "js", "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "ico", "woff", "woff2", "ttf", "mp4", "pdf"]
      transforms   = ["Lowercase"]
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior                = "OverrideAlways"
      cache_duration                = "7.00:00:00"
      compression_enabled           = true
      query_string_caching_behavior = "UseQueryString"
    }
  }

  depends_on = [azurerm_cdn_frontdoor_origin_group.this, azurerm_cdn_frontdoor_origin.appgw]
}

# Route: everything on the endpoint goes to the App Gateway origin group
resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "route-all"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.appgw.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.wordpress.id]
  enabled                       = true

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpOnly" # see README "Hardening": switch to HttpsOnly once App Gateway has a certificate
  https_redirect_enabled = true
  link_to_default_domain = true

  cache {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "text/html", "text/css", "text/plain", "text/xml", "application/javascript",
      "application/json", "application/xml", "image/svg+xml", "font/woff2"
    ]
  }
}

# ---------------- Edge WAF ----------------
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "waf${var.prefix}${var.environment}edge"
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled             = true
  mode                = "Prevention"
  tags                = local.tags

  # Brute-force protection on login endpoints
  custom_rule {
    name                           = "RateLimitLogin"
    enabled                        = true
    priority                       = 100
    type                           = "RateLimitRule"
    action                         = "Block"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 30

    match_condition {
      match_variable = "RequestUri"
      operator       = "Contains"
      match_values   = ["/wp-login.php"]
      transforms     = ["Lowercase"]
    }
  }

  # xmlrpc.php is a common attack target and rarely needed
  custom_rule {
    name     = "BlockXmlRpc"
    enabled  = true
    priority = 110
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable = "RequestUri"
      operator       = "Contains"
      match_values   = ["/xmlrpc.php"]
      transforms     = ["Lowercase"]
    }
  }

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "secpol-waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id
      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
