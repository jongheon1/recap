#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 강의 녹음 → 영어 전사 (OpenAI gpt-4o-transcribe)
#
# m4a/mp3 → 16kHz mono FLAC 변환 → 10분 청크 분할 → 청크별 전사 → 이어붙임.
# 각 청크 경계에 [[t=<초>]] 마커를 남겨서 이후 문단별 대략적 타임스탬프의
# 근거로 쓴다.
#
# 사용법:
#   OPENAI_API_KEY=sk-... bash scripts/transcribe.sh "/경로/강의.m4a"
#   → 같은 경로에 <파일명>.stt.txt 생성
#
# 요구 도구: ffmpeg, curl
# 비용: 분당 약 $0.006 (2시간 ≈ $0.72)
# ─────────────────────────────────────────────────────────────
set -uo pipefail

KEY="${OPENAI_API_KEY:-$(cat ~/.openai_key 2>/dev/null)}"
if [ -z "$KEY" ]; then echo "OPENAI_API_KEY 필요 (.env 또는 ~/.openai_key)" >&2; exit 1; fi
MODEL="gpt-4o-transcribe"
CHUNK_SEC=600            # 10분. 파일당 25MB 제한 → 16kHz mono FLAC 기준 안전
LANG="${STT_LANG:-en}"   # 강의는 영어. 필요시 STT_LANG=ko 등으로 재정의

for SRC in "$@"; do
  if [ ! -f "$SRC" ]; then echo "! 파일 없음: $SRC" >&2; continue; fi
  DIR=$(dirname "$SRC")
  BASE=$(basename "${SRC%.*}")
  OUT="$DIR/${BASE}.stt.txt"
  echo "==================================================" >&2
  echo "[$BASE] 전사 시작" >&2

  WORK=$(mktemp -d)
  # 1) 16kHz mono FLAC 변환
  ffmpeg -y -i "$SRC" -ar 16000 -ac 1 -c:a flac "$WORK/full.flac" -loglevel error
  # 2) 10분 단위 분할
  ffmpeg -y -i "$WORK/full.flac" -f segment -segment_time $CHUNK_SEC -c:a flac \
    "$WORK/part_%03d.flac" -loglevel error
  NCHUNK=$(ls "$WORK"/part_*.flac 2>/dev/null | wc -l | tr -d ' ')
  echo "  청크 $NCHUNK 개" >&2

  : > "$OUT"
  i=0
  for CHUNK in "$WORK"/part_*.flac; do
    T=$((i * CHUNK_SEC))
    i=$((i+1))
    echo "  - 청크 $i/$NCHUNK 전사 중..." >&2
    TXT=""
    for attempt in 1 2 3; do
      TXT=$(curl -sS -m 300 https://api.openai.com/v1/audio/transcriptions \
        -H "Authorization: Bearer $KEY" \
        -F "file=@${CHUNK}" \
        -F "model=${MODEL}" \
        -F "language=${LANG}" \
        -F "response_format=text" 2>/dev/null)
      # 끝 조각이 "corrupted/unsupported"로 실패하면 재인코딩 후 재시도
      if echo "$TXT" | head -c 200 | grep -q '"error"'; then
        echo "    시도 $attempt 실패: $(echo "$TXT" | head -c 150)" >&2
        ffmpeg -y -i "$CHUNK" -c:a flac "$CHUNK.fix.flac" -loglevel error 2>/dev/null && mv "$CHUNK.fix.flac" "$CHUNK"
        TXT=""; sleep 5; continue
      fi
      [ -n "$TXT" ] && break
      sleep 5
    done
    printf '\n[[t=%d]]\n' "$T" >> "$OUT"
    if [ -z "$TXT" ]; then
      printf '[[[청크 %d 전사 실패]]]\n' "$i" >> "$OUT"
    else
      printf '%s\n' "$TXT" >> "$OUT"
    fi
  done
  rm -rf "$WORK"
  echo "  완료 → $OUT ($(wc -m < "$OUT" | tr -d ' ')자)" >&2
done
echo "전체 완료" >&2
