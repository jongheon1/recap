variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token (env: TF_VAR_cloudflare_api_token — never commit)"
}

variable "cloudflare_account_id" {
  type        = string
  default     = "1d3fb81033131596ed3d80980ec10cba"
  description = "Cloudflare Account ID"
}

variable "zone_id" {
  type        = string
  description = "Zone ID of jongheon.click (zone is owned by listen-up's terraform — referenced only)"
}

variable "app_hostname" {
  type        = string
  default     = "recap.jongheon.click"
  description = "Hostname the static site serves on"
}

variable "pages_project_name" {
  type    = string
  default = "recap"
}
