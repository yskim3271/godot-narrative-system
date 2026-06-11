# 시작 가이드 (Getting Started)

10분 안에 "NPC에게 말 걸면 분기 대화가 나오는" 상태까지 갑니다.

## 1. 설치

### 방법 A — 에디터 플러그인 (권장)
1. `addons/narrative_system/` 폴더를 프로젝트의 `addons/`에 복사
2. **프로젝트 → 프로젝트 설정 → 플러그인** 에서 *Narrative System* 활성화
   - `Narrative` autoload와 `narrative_system/database_path` 프로젝트 설정이 자동 등록됩니다
3. 하단 패널에 **Narrative** 탭이 생깁니다 (DB 개요·검증·CSV 도구)

### 방법 B — 수동 (런타임만, 플러그인 없이)
런타임은 에디터 플러그인 없이 완전히 동작합니다:
1. `addons/narrative_system/` 복사
2. **프로젝트 설정 → Autoload** 에 `Narrative` = `res://addons/narrative_system/runtime/narrative.gd` 추가
3. 프로젝트 설정에 `narrative_system/database_path` 항목을 직접 추가하거나, 코드에서 `Narrative.load_database(load("res://my_db.tres"))` 호출

### 제거
플러그인 비활성화(autoload 자동 해제) 후 `addons/narrative_system/` 삭제. 저장 파일(`user://saves/*.json`)은 순수 JSON이라 애드온 제거 후에도 안전합니다.

## 2. 데이터베이스 만들기

1. 파일시스템 독에서 우클릭 → **새 리소스 → NarrativeDatabase** → `narrative_database.tres`로 저장
2. **프로젝트 설정 → Narrative System → Database Path** 에 위 경로 지정 (또는 하단 Narrative 패널에서 Load — 자동으로 설정에 기록됩니다)

## 3. 캐릭터와 변수

Inspector에서 `narrative_database.tres`를 열고:

- **Characters** 배열에 새 `NarrativeCharacter`:
  - `id`: `guard` · `display_name`: `경비병` · `portrait`: 아무 텍스처
- **Variables** 배열에 새 `NarrativeVariable`:
  - `id`: `gold` · `type`: `INT` · `default_int`: `30`

> ⚠ Inspector에서 배열 항목을 **복제하면 같은 인스턴스를 공유**합니다 — 우클릭 → *Make Unique* 를 쓰세요. (검증기가 공유 인스턴스를 에러로 잡아줍니다)

## 4. 첫 대화

**Dialogues** 배열에 새 `NarrativeDialogue`:
- `id`: `hello` · `start_node_id`: `n1`
- `nodes`에 `NarrativeDialogueNode` 두 개:

| 필드 | 노드 1 | 노드 2 |
|---|---|---|
| id | `n1` | `n2` |
| speaker_id | `guard` | `guard` |
| text | `멈춰라! 누구냐?` | `지나가도 좋다.` |
| choices | (아래 두 개) | (없음) |
| next_node_id | (비움) | (비움 = 대화 종료) |

노드 1의 `choices`에 `NarrativeChoice` 두 개:

| 필드 | 선택지 1 | 선택지 2 |
|---|---|---|
| id | `pay` | `leave` |
| text | `통행료를 내겠소 (10골드)` | `그냥 가겠소` |
| condition | `gold >= 10` | (비움) |
| actions | `gold -= 10` | (비움) |
| target_node_id | `n2` | (비움 = 종료) |
| show_disabled | ✓ (조건 미달 시 회색 표시) | |

## 5. UI와 시작 코드

게임 씬에 인스턴스 추가: `addons/narrative_system/ui/dialogue_box.tscn`, `choice_list.tscn` (autoload에 자동 연결됩니다).

```gdscript
# NPC 상호작용 등에서:
func _on_interact() -> void:
	Narrative.start_dialogue("hello")

func _ready() -> void:
	Narrative.dialogue_started.connect(func(_id): set_physics_process(false))
	Narrative.dialogue_ended.connect(func(_id): set_physics_process(true))
```

실행 → 대화창과 선택지가 뜨고, Enter/클릭으로 진행, 골드가 부족하면 선택지가 비활성으로 보입니다.

## 6. 검증 습관

- 하단 **Narrative 패널 → Validate**: 끊어진 링크, 없는 id, 조건식 오타(`=` vs `==`), 도달 불가 노드 등을 한 번에 검출
- CI/터미널: 
  ```
  godot --headless --path . -s res://addons/narrative_system/validation/validate_cli.gd -- --db=res://narrative_database.tres
  ```

## 다음 단계

- 분기 패턴·저작 요령: [dialogue_authoring.md](dialogue_authoring.md)
- 조건/액션 문법 전체: [dsl.md](dsl.md)
- 퀘스트 연결: [quest_system.md](quest_system.md)
- 전체 데모 코드 읽기: [examples/integrated_demo](../examples/integrated_demo/README.md)
