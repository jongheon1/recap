# recap — 영어 강의 녹음 → 영/한 대역 리딩 문서

영어 강의 녹음(수십 분~수 시간)을 전사·교정·번역해서 웹에서 영어 원문과 한국어
번역을 나란히 읽을 수 있게 만드는 도구. listen-up(문장 단위 듣기 훈련)의 자매
프로젝트로, 이쪽은 **내용 이해를 위한 문서 리더**다.

## 아키텍처: 처리는 Claude Code가, 호스팅은 정적으로

- **웹은 100% 정적.** Cloudflare Pages가 `web/`을 서빙하고, 데이터(강의 목록·
  결과 문서)도 전부 `web/data/`의 정적 JSON이다. 서버·Worker·DB 없음.
- **처리 파이프라인의 런타임은 Claude Code 자신이다.** 별도 데몬·서버 없음.
  사용자가 Claude Code에게 녹음 파일 처리를 시키면, Claude Code가 아래
  "처리 파이프라인"을 직접 수행하고 배포까지 한다.
- **번역·교정도 Claude Code(서브에이전트)가 직접 한다. Anthropic API 키 불필요.**
- 외부 의존성은 STT용 OpenAI API 하나뿐이다.

```
사용자: "이 녹음 처리해줘" ──▶ Claude Code
  1. scripts/transcribe.sh  (ffmpeg 청크 → gpt-4o-transcribe)
  2. 서브에이전트 병렬: 교정 + 문단 분할 + 한국어 번역
  3. web/data/results/<id>.json 생성, web/data/index.json 갱신
  4. git commit → wrangler pages deploy
                              ──▶ https://recap.jongheon.click
```

## 새 PC 셋업

1. `git clone https://github.com/jongheon1/recap && cd recap`
2. `cp .env.example .env` 후 키 입력:
   - `OPENAI_API_KEY` — 전사에 필수
   - `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` — 배포에 필수
3. 도구 확인: `ffmpeg`(필수, `brew install ffmpeg`), `node`+`npx`(배포용),
   `terraform`(인프라 변경 시에만)

## 처리 파이프라인 (Claude Code 작업 지침)

사용자가 오디오 파일과 코스(과목)를 지정하며 처리를 요청하면 아래를 순서대로
수행한다. 코스가 처음 나오는 것이면 `web/data/index.json`에 새 코스를 추가한다.

### 1. 전사

```bash
set -a; source .env; set +a
bash scripts/transcribe.sh "<오디오 파일>"
```

- 산출물: 오디오 옆 `<파일명>.stt.txt`. `[[t=<초>]]` 마커가 10분 간격으로 있다.
- 오디오 파일과 `.stt.txt`는 **절대 커밋하지 않는다** (.gitignore에 있음).
- 2시간 녹음 기준 약 12청크, 10분 내외 소요. `run_in_background`로 돌리고
  완료를 기다릴 것.

### 2. 교정 + 문단 분할 + 번역 (서브에이전트 병렬)

전사 텍스트를 **20~30분 분량(t 마커 기준 2~3청크)씩 나눠** 서브에이전트에게
병렬로 맡긴다. 각 에이전트에게 직전 조각의 마지막 문단(영어)을 문맥으로 함께
제공해 경계가 자연스럽게 이어지게 한다.

각 서브에이전트에게 줄 지침:

- **교정**: 명백한 STT 오인식만 교정한다. 추측 편집 금지. 강의 주제/과목명을
  참고해 전문용어 오인식을 바로잡는다 (예: "b tree" → "B-tree").
  같은 단락이 반복 출력된 STT 환각은 1회로 줄인다. 필러(um, uh)는 제거하되
  말투는 유지한다.
- **문단 분할**: 화제 전환 기준으로 3~6문장씩. 강의 흐름(개념 도입 → 예시 →
  정리)이 단위가 되도록.
- **번역**: 문단별 한국어 번역. 전공 용어는 한국 전공서 표준 역어 + 필요시
  원어 병기. 직역보다 강의 말투가 살아있는 자연스러운 한국어.
- **출력**: 아래 JSON만 반환 (문단마다 해당 구간의 `[[t=]]` 마커 값 사용):

```json
{"paragraphs": [{"t": 1200, "en": "...", "ko": "..."}]}
```

완료 후 조각들을 순서대로 합치고 검증한다: JSON 파싱 가능, 모든 문단에
en/ko 존재, 문단 수가 원문 분량 대비 타당한지 (2시간 강의 ≈ 60~150문단).

### 3. 결과 JSON 생성

`web/data/results/<id>.json` — id는 `YYYY-MM-DD-<slug>` (예: `2026-07-10-os-scheduling`):

```json
{
  "id": "2026-07-10-os-scheduling",
  "course": "os",
  "title": "CPU Scheduling",
  "date": "2026-07-10",
  "duration_sec": 5400,
  "paragraphs": [{"t": 0, "en": "...", "ko": "..."}]
}
```

`web/data/index.json` 갱신 — 해당 코스의 `files` 맨 앞에 추가:

```json
{
  "courses": [
    {
      "id": "os",
      "name": "Operating Systems",
      "files": [
        {"id": "2026-07-10-os-scheduling", "title": "CPU Scheduling",
         "date": "2026-07-10", "duration_sec": 5400, "paragraphs": 87}
      ]
    }
  ]
}
```

### 4. 커밋 + 배포

```bash
git add web/data && git commit -m "<코스>: <제목> 추가"
set -a; source .env; set +a
npx wrangler pages deploy web --project-name recap --branch main --commit-dirty=true
```

배포 후 사용자에게 문서 URL을 보고한다:
`https://recap.jongheon.click/#/r/<id>`

## 데이터 스키마 요약

- `web/data/index.json` — 코스 목록. 각 코스: `{id, name, files[]}`,
  각 파일: `{id, title, date, duration_sec, paragraphs}`
- `web/data/results/<id>.json` — 문서 본문. `{id, course, title, date,
  duration_sec, paragraphs: [{t, en, ko}]}`
- `t`는 문단이 시작되는 대략적 재생 위치(초). 지금은 화면에 안 쓰지만
  나중에 오디오 점프 기능을 위해 유지한다.

## 인프라 (Terraform)

**Cloudflare 리소스 변경은 반드시 `infra/`의 Terraform으로만 한다.**
대시보드 수동 변경 금지. wrangler는 Pages 배포(콘텐츠 업로드)에만 쓴다.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # gitignored — zone_id 등 입력
set -a; source ../.env; set +a
TF_VAR_cloudflare_api_token=$CLOUDFLARE_API_TOKEN terraform init && terraform apply
```

리소스: Pages 프로젝트(`recap`), DNS CNAME(`recap.jongheon.click` →
Pages 서브도메인), Pages 커스텀 도메인 연결. zone(`jongheon.click`)은
listen-up 인프라가 소유하므로 여기서는 zone_id 변수로만 참조한다.

## 보안 규칙 (절대 규칙)

- **API 키·토큰을 파일로 커밋하지 않는다.** 비밀은 `.env`와
  `infra/terraform.tfvars`에만 두며 둘 다 gitignored다. 커밋 전 diff에서
  `sk-`, 토큰 문자열이 보이면 중단하고 사용자에게 알린다.
- 강의 녹음 원본·전사 텍스트(`.stt.txt`)는 커밋하지 않는다 (저작권·프라이버시).
  웹에 올라가는 것은 교정·번역된 결과 JSON뿐이다.
- terraform state(`*.tfstate`)도 커밋하지 않는다.
