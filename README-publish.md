# 자동 발행 구조 (블로그 공통)

- `_drafts/NN-slug.md` : 초안. front matter 에 `status: ready` 가 있어야 발행 대상.
- `tools/publish_next.ps1` : ready 초안 중 파일명 순서 첫 번째를 `_posts/YYYY-MM-DD-slug.md` 로 옮기고 `date` 를 넣고 `status` 를 지운다. git 은 건드리지 않는다.
- `.github/workflows/publish.yml` : 매주 화 09:00 KST(월 00:00 UTC) 실행, 변경이 있으면 커밋·push.
- 새 블로그(예: 자동화 블로그)는 `tools/`, `.github/`, `.gitignore` 를 그대로 복사하고 `_config.yml`, `index.md`, `about.md`, 초안만 바꾼다.
- 로컬 확인: `powershell -File tools/publish_next.ps1 -Site . -DryRun`
- 비밀 값(토큰 등)은 저장소에 두지 않는다. 이 구조는 `GITHUB_TOKEN` 외 비밀 값이 필요 없다.

## 글 그림 만들기
- `powershell -File tools/make_images.ps1` 한 번이면 _drafts·_posts의 모든 글에 대해 ssets/img/<글 slug>/에 cover.svg, cover.png, card.svg, steps.svg를 만들고 본문(인사 카드·전과 후 아래)과 front matter(image:)에 연결한다. 글에 적힌 값만 그리며, 여러 번 실행해도 같은 결과가 나온다.
- cover.png는 SNS 미리보기용이라 Windows PowerShell에서만 만들어진다(없으면 cover.svg로 대체). 글 한 편만: `-Post _drafts/파일.md`.
