# Branching Choice Demo

선택지·조건 분기 데모이자 **텍스트 저작(.ndlg) 워크플로** 예제입니다.

- 대화 내용은 전부 [branching.ndlg](branching.ndlg)에 있습니다 — 작가는 이 텍스트 파일만 수정하면 됩니다. [branching.gd](branching.gd)는 캐릭터/변수만 코드로 만들고 `dialogue_script_parser`로 임포트합니다.
- 확인할 것:
  - **첫만남/재방문 인사 변형** (`has_seen` 조건 라우팅 패턴)
  - "사과를 사겠소 (5골드)" — 골드 12로 시작: 두 번 사면 잔액 2골드 → **회색 비활성**(`show_disabled`)
  - "나는 부자라네" — 골드 100 미만이면 **숨김** (조건 + show_disabled 없음)
  - 메뉴 루프(구매 후 메뉴로 복귀) — 그래프 순환이 합법인 예
- 조작: 방향키 이동 · **E** 대화

텍스트 포맷 문법: [docs/text_script.md](../../docs/text_script.md)
