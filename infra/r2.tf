# 강의 오디오 재생용 스토리지. 정적 사이트 구조를 유지하기 위해 워커/백엔드 없이
# R2의 Public Development URL(r2.dev)로 직접 서빙한다. 업로드는
# scripts/upload-audio.sh(wrangler r2 object put)로 한다.
resource "cloudflare_r2_bucket" "audio" {
  account_id = var.cloudflare_account_id
  name       = var.r2_bucket_name
  location   = "APAC"
}

resource "cloudflare_r2_managed_domain" "audio" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.audio.name
  enabled     = true
}

output "audio_bucket_name" {
  value = cloudflare_r2_bucket.audio.name
}

# apply 후 이 값을 ../.env 의 AUDIO_BASE_URL 에 넣는다.
output "audio_public_domain" {
  value = "https://${cloudflare_r2_managed_domain.audio.domain}"
}
