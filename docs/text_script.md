# 텍스트 대화 스크립트 (.ndlg)

작가 친화적인 평문 포맷으로 대화를 저작하고 `NarrativeDialogue` 리소스로 임포트합니다. Inspector/그래프 에디터와 **혼용 가능** — export로 되돌릴 수 있어 왕복이 보장됩니다.

## 사용법

```gdscript
const ScriptParser := preload("res://addons/narrative_system/import_export/dialogue_script_parser.gd")
var report := ScriptParser.import_file(db, "res://dialogues/chapter1.ndlg")
# report: {ok, imported, replaced, skipped, errors:[{line, message}]}
var text := ScriptParser.export_dialogue(db.get_dialogue("guard_talk"))
```
- 에디터: 하단 **Narrative 패널 → Import Script** (임포트 후 .tres 자동 저장)
- **임포트는 원자적**: 파스 에러가 하나라도 있으면 데이터베이스를 건드리지 않고 줄 번호와 함께 보고합니다
- 같은 id의 대화는 제자리 교체(기본) 또는 건너뛰기(`replace_existing = false`)
- 실전 예제: [examples/branching_choice_demo/branching.ndlg](../examples/branching_choice_demo/branching.ndlg)

## 문법

라인 기반 · 들여쓰기는 무시(가독성용) · 줄 시작이 `#`이면 주석 · 키워드가 줄을 시작합니다.

```
dialogue guard_talk          # 새 대화 (한 파일에 여러 개 가능)
title 경비병 대화             # 선택 (기본: id)
start g_first                # 선택 (기본: 첫 node)

node g_first
speaker guard                # 비우면 나레이터
key dlg.guard_talk.g_first.text   # 명시 로컬라이징 키 (선택)
if not has_seen("guard_talk", "g_first")   # 조건 (노드당 1개)
do met_guard = true          # 액션 — 반복하면 줄로 누적
do gold += 1
text 처음 보는 얼굴이군.       # 본문 — 반복하면 줄바꿈으로 누적
text 무슨 일로 왔나?
seq set_expression("guard", "angry")       # 시퀀서 명령 — 반복 누적
next g_menu                  # advance 대상 (비우면 종료)

node g_menu
text 용건을 말해보게.
choice c_quest -> q_give     # 선택지: id -> 타깃 ("->"만 쓰거나 생략 = 대화 종료)
  text 일거리가 있나?          # choice 다음의 text/if/do/key는 그 선택지에 부착
  if quest_state("rat_hunt") == "inactive"
  do gold -= 1
  show_disabled              # 조건 미달 시 회색 표시 (없으면 숨김)
choice c_bye ->
  text 아무것도 아닐세.
```

### 부착 규칙 (중요)
- `choice` 이후의 `text`/`if`/`do`/`key`는 **그 선택지**에 붙습니다 — 노드 레벨 `text`/`if`/`do`는 **첫 choice보다 먼저** 써야 합니다(어기면 줄 번호와 함께 에러).
- `speaker`/`seq`/`next`는 항상 노드 레벨입니다(위치 무관).
- `if`/`key`는 대상당 1개(중복 시 에러 — 조건은 `and`로 합치세요).

### 기타 규칙
- id 문자셋: `[a-zA-Z0-9_.]` (대화/노드/선택지/타깃 전부)
- `start`가 가리키는 노드는 같은 대화 안에 있어야 합니다(앞쪽 선언이 아니어도 됨)
- 인라인 `#`은 주석이 아닙니다(본문에 # 사용 가능) — 주석은 줄 시작에서만
- UTF-8 BOM·CRLF 자동 처리
- 그래프 배치(metadata)는 포맷에 포함되지 않습니다 — 임포트 후 그래프 에디터가 자동 배치

## 한계
- 캐릭터/퀘스트/변수/번역 테이블은 포맷 밖입니다(코드·Inspector로 저작) — 대화 전용 포맷
- 임포트로 기존 대화를 교체하면 그래프 노드 배치가 초기화됩니다(자동 배치로 복구)
