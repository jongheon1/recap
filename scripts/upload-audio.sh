#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 강의 오디오를 R2(recap-audio 버킷)에 업로드하고 공개 URL을 stdout으로 출력.
#
# 사용법:
#   set -a; source .env; set +a
#   bash scripts/upload-audio.sh "<오디오 파일>" "<문서 id>"
#   → https://pub-xxxx.r2.dev/<id>.<ext>
#
# 요구: .env에 CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, AUDIO_BASE_URL
#   (AUDIO_BASE_URL은 infra/ apply 후 `terraform output audio_public_domain`)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SRC="${1:?사용법: upload-audio.sh <오디오 파일> <문서 id>}"
ID="${2:?사용법: upload-audio.sh <오디오 파일> <문서 id>}"
BUCKET="${R2_BUCKET_NAME:-recap-audio}"

if [ ! -f "$SRC" ]; then echo "! 파일 없음: $SRC" >&2; exit 1; fi
if [ -z "${AUDIO_BASE_URL:-}" ]; then echo "AUDIO_BASE_URL 필요 (.env)" >&2; exit 1; fi

EXT="${SRC##*.}"
KEY="${ID}.${EXT}"

echo "[$ID] R2 업로드 중... (${BUCKET}/${KEY})" >&2
npx wrangler r2 object put "${BUCKET}/${KEY}" --file "$SRC" --remote >&2

echo "${AUDIO_BASE_URL%/}/${KEY}"
