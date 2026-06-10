# Signal 계약

모든 시그널은 **상태 변경 완료 후 동기 방출**된다(헤드리스 테스트 결정성). 파사드 `Narrative`(autoload)가 서브시스템 시그널을 동일 이름으로 재방출하므로 게임 코드는 파사드만 구독하면 된다.

## 1. 시그널 목록

| 시그널 | 방출 주체 | 인자 | 주 구독자 |
|---|---|---|---|
| `dialogue_started(dialogue_id)` | DialogueRunner | String | 게임 코드(조작 잠금 등) |
| `dialogue_resumed(dialogue_id, node_id)` | DialogueRunner | String, String | DialogueBox (저장 복원 시) |
| `node_entered(node_id)` | DialogueRunner | String | 디버그/히스토리 도구 |
| `line_presented(speaker_id, text)` | DialogueRunner | String, String | DialogueBox |
| `choices_presented(choices)` | DialogueRunner | Array[Dictionary] | ChoiceList |
| `choice_selected(choice_id)` | DialogueRunner | String | ChoiceList, 게임 코드 |
| `dialogue_ended(dialogue_id)` | DialogueRunner | String | UI 숨김, 게임 코드(조작 해제) |
| `expression_changed(character_id, expression)` | DialogueRunner/Sequencer | String, String | DialogueBox 초상화 |
| `variable_changed(variable_id, value)` | NarrativeState | String, Variant | 게임 코드, QuestTracker |
| `quest_updated(quest_id)` | QuestManager | String | QuestLog, QuestTracker, Alert 글루 |
| `language_changed(locale)` | LocalizationManager | String | 모든 UI 재렌더 |
| `alert_requested(text)` | 파사드 | String | AlertUI 큐 |
| `bark_requested(character_id, text, attach_to)` | 파사드 | String, String, Node | BarkUI |

`choices_presented`의 각 항목: `{ "id": String, "text": String, "enabled": bool }`. 조건 미충족 선택지는 기본 **제외**(숨김), 선택지 메타데이터 `show_disabled = true`면 `enabled=false`로 포함.

## 2. 한 스텝의 방출 순서

`start_dialogue("guard_intro")` 기준:

```
dialogue_started("guard_intro")
node_entered("start")
(variable_changed / quest_updated ...)   ← 노드 액션의 부수효과
line_presented("guard", "멈춰라!")
choices_presented([...])                 ← 보이는 선택지가 있을 때만
(이후 시퀀서 런이 병행 시작 — emit_signal/call_method 명령은 여기서 발생)
```

`select_choice(id)`: `choice_selected(id)` → (선택지 액션 부수효과) → 다음 노드의 `node_entered` ... / 타깃 없으면 `dialogue_ended`.

## 3. 구독 패턴

```gdscript
func _ready() -> void:
    Narrative.dialogue_started.connect(_on_dialogue_started)
    Narrative.dialogue_ended.connect(_on_dialogue_ended)
    Narrative.quest_updated.connect(_on_quest_updated)
```

UI가 대화 도중 늦게 인스턴스되면 `_ready`에서 `Narrative.get_current_node()`/`get_available_choices()`를 1회 풀(pull)해 현재 상태를 그린다(이후는 시그널만).

## 4. 재진입 규칙 (구독자가 지켜야 할 것)

- `line_presented` 핸들러에서 `advance()` 호출 가능(자동 진행) — 러너가 큐잉 처리.
- `choices_presented` 핸들러에서 `advance()`는 불법(경고+무시) — 선택지 표시 중에는 `select_choice()`만.
- 시그널 핸들러에서 `start_dialogue()` 호출은 거부됨 — 대화 종료 후 호출할 것.
