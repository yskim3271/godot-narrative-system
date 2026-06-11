# API 레퍼런스 — `Narrative` 파사드 (autoload)

게임 코드가 사용하는 단일 진입점입니다. 모든 서브시스템 시그널을 같은 이름으로 재방출합니다. (autoload 없이 쓰는 법: [extending.md](extending.md) §4)

## 시그널

| 시그널 | 시점 |
|---|---|
| `dialogue_started(dialogue_id)` / `dialogue_ended(dialogue_id)` | 대화 시작/종료 (입력 잠금/해제 지점) |
| `dialogue_resumed(dialogue_id, node_id)` | 저장 로드로 대화 위치가 재개될 때 (직후 line_presented 따라옴) |
| `node_entered(node_id)` | 노드 진입(조건 스킵된 노드 포함) |
| `line_presented(speaker_id, text)` | 표시할 대사 확정 (로컬라이즈된 텍스트) |
| `choices_presented(choices)` | 선택 대기 — `[{id, text, enabled}]` |
| `choice_selected(choice_id)` | 선택 직후 (액션 실행 전) |
| `expression_changed(character_id, expression)` | 초상화 표정 변경 |
| `variable_changed(variable_id, value)` | 변수 값이 실제로 바뀔 때 |
| `quest_updated(quest_id)` | 퀘스트 상태/objective/추적 변경 |
| `objective_completed(quest_id, objective_id)` | objective가 완료로 넘어가는 순간 (수동 진행/자동 완료 조건 모두) |
| `language_changed(locale)` | 언어 전환 |
| `alert_requested(text)` / `bark_requested(character_id, text, attach_to)` | 알림/바크 (로컬라이즈 완료된 텍스트) |
| `sequence_event(event_name, args)` | 시퀀서 `emit_signal` 명령 |
| `sequencer_message(message)` | 시퀀서 메시지 브로드캐스트 (`-> "name"` 또는 `send_sequencer_message`) |

## 대화

| 메서드 | 설명 |
|---|---|
| `start_dialogue(dialogue_id, start_node_id := "") -> bool` | 시작 (실행 중이면 거부 — `end_dialogue()` 먼저) |
| `advance() -> bool` | 다음 라인 (선택지 표시 중엔 불가) |
| `select_choice(choice_id) -> bool` | 선택 (숨김/비활성/미지 id 거부) |
| `end_dialogue() -> bool` | 즉시 종료 |
| `is_dialogue_running() / is_waiting_for_choice() -> bool` | 상태 |
| `get_current_dialogue_id() -> String` · `get_current_node() -> NarrativeDialogueNode` | 현재 위치 |
| `get_current_line_text() -> String` · `get_available_choices() -> Array[Dictionary]` | 늦은 UI 부착용 풀 |
| `get_character(id) -> NarrativeCharacter` · `get_character_display_name(id) -> String` | 화자 정보(이름은 로컬라이즈) |

시그널 핸들러 안에서의 `advance()`/`select_choice()`는 내부 큐로 안전 처리됩니다. 자세한 재진입 규칙: [signals.md](signals.md).

## 변수

`get_variable(id) -> Variant` · `set_variable(id, value) -> bool` (선언 타입으로 강제 변환) · `has_variable(id) -> bool`

## 퀘스트

| 메서드 | 설명 |
|---|---|
| `start_quest(id)` / `complete_quest(id, force := false)` / `fail_quest(id)` | 상태 전이 (`-> bool`) — repeatable 퀘스트는 completed/failed에서도 `start_quest` 재시작 가능 |
| `abandon_quest(id) -> bool` | active 퀘스트 포기 → inactive (진행도 폐기, 완료 이력 보존) |
| `get_times_completed(id) -> int` | 누적 완료 횟수 (반복 퀘스트) |
| `update_objective(quest_id, objective_id, delta := 1) -> bool` | 진행 (클램프) — objective의 `auto_complete_condition`은 변수 변경 시 자동 평가 |
| `get_quest_state(id) -> String` | `"inactive" / "active" / "completed" / "failed"` |
| `is_quest_active/completed/failed(id) -> bool` · `are_all_objectives_completed(id) -> bool` | 질의 |
| `get_quests_in_state(state) -> Array[String]` · `get_tracked_quests() -> Array[String]` | 목록(정렬) |
| `get_quest_category(id) -> String` · `get_quest_categories() -> Array[String]` · `get_quests_in_category(category, state := "") -> Array[String]` | 카테고리 |
| `set_quest_tracked(id, on) -> bool` · `is_quest_tracked(id) -> bool` | 트래커 |
| `get_quest_title/get_quest_description(id) -> String` · `get_objectives_progress(id) -> Array[Dictionary]` | UI용(로컬라이즈) — progress 항목: `{id, text, count, target, completed}` |

## 저장 / 로드

`save_game(slot := "save") -> Error` · `load_game(slot := "save") -> Error` · `has_save(slot) -> bool` · `delete_save(slot) -> bool`

## 로컬라이징

`set_language(locale)` · `get_language() -> String` · `get_ui_text(key, fallback := "") -> String`

## 알림 / 바크 / 시퀀스 / 확장

| 메서드 | 설명 |
|---|---|
| `show_alert(text_or_key)` | AlertUI 큐로 표시 (키면 번역) |
| `bark(character_id, text_or_key, attach_to := null)` | 말풍선 (기본 attach: 등록된 액터 노드) |
| `play_sequence(source, label := "api")` | 시퀀서 명령 직접 실행 |
| `send_sequencer_message(message)` | `@ message("name")` 대기 라인 해제 ([sequencer.md](sequencer.md)) |
| `register_function(name, callable, override := false) -> bool` | DSL 함수 등록 |
| `register_sequencer_command(name, callable, override := false) -> bool` | 시퀀서 명령 등록 |
| `register_actor(id, node)` / `unregister_actor(id)` / `get_actor(id) -> Node` | 액터 레지스트리 |
| `load_database(db) -> bool` · `is_ready() -> bool` · `context: NarrativeContext` | 수명/고급 접근 |

## 고급: `Narrative.context`

파사드가 다루지 않는 세부는 컨텍스트로 직접: `context.state`(custom_data, history, seen) · `context.localization`(missing_keys) · `context.quests`(get_objective_count) · `context.save_manager`(capture/apply, migrations) · `context.evaluator` · `context.sequencer`. 클래스 주석(`##`)이 각 API의 1차 문서입니다.

## 데이터 클래스 (저작)

`NarrativeDatabase` · `NarrativeSettings` · `NarrativeCharacter` · `NarrativeDialogue` · `NarrativeDialogueNode` · `NarrativeChoice` · `NarrativeQuest` · `NarrativeQuestObjective` · `NarrativeVariable` · `NarrativeLocalizationTable` — 필드는 [dialogue_authoring.md](dialogue_authoring.md)와 각 스크립트의 Inspector 툴팁 참고. **전부 런타임 불변**(런타임 상태는 NarrativeState).
