# recap

영어 강의 녹음을 전사·교정·번역해서 영어 원문 / 한국어 번역을 나란히 읽는
정적 웹 문서로 만들어주는 도구. **처리 파이프라인의 런타임은 Claude Code다** —
이 레포를 클론하고 `.env`에 키를 넣은 뒤 Claude Code에게 녹음 파일을 건네면
전사부터 배포까지 알아서 한다. 절차 전체는 [CLAUDE.md](CLAUDE.md)에 있다.

- 웹: https://recap.jongheon.click (Cloudflare Pages, 100% 정적)
- STT: OpenAI `gpt-4o-transcribe` (ffmpeg 10분 청크)
- 교정·문단화·번역: Claude Code 서브에이전트 (별도 API 키 불필요)
- 인프라: Terraform (`infra/`)

## 빠른 시작

```bash
git clone https://github.com/jongheon1/recap && cd recap
cp .env.example .env   # OPENAI_API_KEY, CLOUDFLARE_API_TOKEN 입력
claude                 # → "audio/오늘강의.m4a 처리해줘, 코스는 os"
```

자매 프로젝트: [listen-up](https://github.com/jongheon1/listen-up) —
문장 단위 듣기 훈련용 오디오 플레이어. recap은 내용 이해용 문서 리더.
