#!/usr/bin/env python3
"""
결과 JSON의 문단 t(재생 시각)를, 실제 세그먼트 타임스탬프가 있는 새 STT
전사본(whisper-1 verbose_json 기반, [[t=N]] 마커가 세그먼트마다 있음)과
대조해서 다시 계산한다.

기존 t는 (구 파이프라인에서) 10분 청크 안에서 텍스트 길이 비례로 어림짐작한
값이라 뒤로 갈수록 오차가 누적됐다. 이 스크립트는 각 문단의 시작 문장을
새 전사본의 실제 세그먼트와 매칭해서 그 세그먼트의 실제 시각으로 교체한다.

매칭은 old_t 주변의 시간 창(window)으로 검색 범위를 제한한다 — 기존 t가
완전히 엉터리는 아니고(청크 경계 기준으로는 맞음) "그 근방 어딘가"라는
정보이므로, 이걸 활용해야 텍스트가 우연히 비슷한 먼 구간으로 잘못 매칭되는
걸 막을 수 있다.

사용법:
    python3 scripts/realign-timestamps.py <결과.json> <새 stt.txt> [--apply]

--apply 없이 실행하면 old→new diff만 보여주고 파일은 안 건드린다.
"""
import sys
import re
import json
import difflib

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "so", "to", "of", "in", "on", "is",
    "it", "you", "i", "we", "that", "this", "was", "were", "are", "be",
    "for", "with", "as", "at", "by", "from", "have", "has", "had", "not",
    "your", "our", "my", "if", "will", "can", "do", "does", "did",
}

def parse_stt(path):
    """[[t=N]] 마커로 나뉜 (t:int, text:str) 세그먼트 리스트를 반환."""
    text = open(path, encoding="utf-8").read()
    parts = re.split(r"\[\[t=(\d+)\]\]", text)
    segs = []
    for i in range(1, len(parts), 2):
        t = int(parts[i])
        body = parts[i + 1].strip()
        if body:
            segs.append((t, body))
    segs.sort(key=lambda s: s[0])
    return segs

def norm_words(s):
    s = s.lower()
    s = re.sub(r"[^a-z0-9']+", " ", s)
    return [w for w in s.split() if w]

def signal_words(words, n=40):
    """흔한 불용어를 걸러낸, 매칭에 신호가 되는 단어 집합(순서 보존 앞부분)."""
    sig = [w for w in words if w not in STOPWORDS]
    return sig[:n] if sig else words[:n]

def overlap_score(para_sig, window_words):
    wset = set(window_words)
    if not para_sig:
        return 0.0
    hits = sum(1 for w in para_sig if w in wset)
    return hits / len(para_sig)

def best_match(para_words, segs, seg_index_by_time, lo_t, hi_t, anchor_t, max_segs=20):
    """[lo_t, hi_t] 시간 범위 안의 세그먼트만 후보로 두고 최적 시작점을 찾는다.
    윈도우 크기는 고정 개수가 아니라 para_sig 단어 수만큼 찰 때까지 세그먼트를
    누적한다 — whisper 세그먼트는 2~4단어로 아주 짧을 때가 많아서, 고정
    세그먼트 개수로는 진짜 일치도 낮은 점수로 걸러질 수 있기 때문.
    점수가 같으면 anchor_t(기존 추정 t)에 더 가까운 후보를 우선한다."""
    para_sig = signal_words(para_words)
    target_words = max(len(para_sig), 8)
    lo_i = seg_index_by_time(lo_t)
    hi_i = seg_index_by_time(hi_t)
    best_t, best_score, best_dist = None, 0.0, None
    for i in range(lo_i, min(hi_i + 1, len(segs))):
        acc = []
        for w in range(max_segs):
            j = i + w
            if j >= len(segs) or segs[j][0] > hi_t:
                break
            acc.extend(norm_words(segs[j][1]))
            if len(acc) >= target_words:
                break
        score = overlap_score(para_sig, acc)
        dist = abs(segs[i][0] - anchor_t)
        if best_t is None or score > best_score or (score == best_score and dist < best_dist):
            best_t, best_score, best_dist = segs[i][0], score, dist
    return best_t, best_score

def make_time_index(segs):
    times = [s[0] for s in segs]
    def idx_for_time(t):
        # 첫 seg with time >= t (bisect)
        lo, hi = 0, len(times)
        while lo < hi:
            mid = (lo + hi) // 2
            if times[mid] < t:
                lo = mid + 1
            else:
                hi = mid
        return min(lo, len(segs) - 1)
    return idx_for_time

def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    result_path = sys.argv[1]
    stt_path = sys.argv[2]
    apply = "--apply" in sys.argv[3:]

    doc = json.load(open(result_path, encoding="utf-8"))
    segs = parse_stt(stt_path)
    if not segs:
        print(f"! {stt_path}: 세그먼트를 못 찾음 (구 포맷 STT?)", file=sys.stderr)
        sys.exit(1)
    idx_for_time = make_time_index(segs)

    BACK_MARGIN = 90      # old_t보다 이만큼까지는 과거도 허용 (초)
    FWD_MARGIN = 200       # old_t보다 이만큼까지 미래도 허용 (초) — 청크 내 드리프트 상한
    MIN_SCORE = 0.4

    prev_new_t = -1
    changes = []
    for p in doc["paragraphs"]:
        pw = norm_words(p["en"])
        lo_t = max(0, p["t"] - BACK_MARGIN, prev_new_t)
        hi_t = p["t"] + FWD_MARGIN
        t, score = best_match(pw, segs, idx_for_time, lo_t, hi_t, p["t"])
        if t is None or score < MIN_SCORE:
            changes.append((p["t"], p["t"], 0.0, p["en"][:60]))
            continue
        changes.append((p["t"], t, score, p["en"][:60]))
        p["_new_t"] = t
        prev_new_t = t

    print(f"{result_path}")
    print(f"{'old_t':>7}  {'new_t':>7}  {'Δ':>6}  score  text")
    for old_t, new_t, score, snippet in changes:
        delta = new_t - old_t
        flag = "  <=== 매칭 실패/저신뢰 (기존 t 유지)" if score < MIN_SCORE else ""
        print(f"{old_t:7d}  {new_t:7d}  {delta:+6d}  {score:0.2f}  {snippet}{flag}")

    low_conf = sum(1 for *_, score, _ in changes if score < MIN_SCORE)
    if low_conf:
        print(f"\n! 매칭 실패/저신뢰 {low_conf}건 — 적용 전 육안 확인 권장", file=sys.stderr)

    if apply:
        for p in doc["paragraphs"]:
            if "_new_t" in p:
                p["t"] = p.pop("_new_t")
        prev = -1
        for p in doc["paragraphs"]:
            if p["t"] <= prev:
                p["t"] = prev + 1
            prev = p["t"]
        json.dump(doc, open(result_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        print(f"\n✓ 적용 완료 → {result_path}")
    else:
        print("\n(--apply 없음 — 파일 미변경)")

if __name__ == "__main__":
    main()
