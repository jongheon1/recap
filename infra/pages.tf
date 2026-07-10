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
# DNS-only (unproxied): 사내망이 CF 프록시 anycast 대역(104.21.x/172.67.x)을
# 차단해서 proxied=true면 회사에서 접속 불가. listen-up과 동일하게 유지.
resource "cloudflare_dns_record" "app" {
  zone_id = var.zone_id
  name    = var.app_hostname
  type    = "CNAME"
  content = data.cloudflare_pages_project.site.subdomain
  ttl     = 300
  proxied = false
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
