resource "cloudflare_pages_project" "site" {
  account_id        = var.cloudflare_account_id
  name              = var.pages_project_name
  production_branch = "main"
}

data "cloudflare_pages_project" "site" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.site.name
}

# recap.jongheon.click → Pages
resource "cloudflare_dns_record" "app" {
  zone_id = var.zone_id
  name    = var.app_hostname
  type    = "CNAME"
  content = data.cloudflare_pages_project.site.subdomain
  ttl     = 1 # auto, required when proxied
  proxied = true
}

resource "cloudflare_pages_domain" "site" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.site.name
  name         = var.app_hostname
  depends_on   = [cloudflare_dns_record.app]
}

output "pages_subdomain" {
  value = data.cloudflare_pages_project.site.subdomain
}

output "url" {
  value = "https://${var.app_hostname}"
}
