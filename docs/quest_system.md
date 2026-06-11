# 퀘스트 시스템

## 상태 모델

```
inactive ──start_quest()──▶ active ──complete_quest()──▶ completed
   ▲                          │  └─────fail_quest()────▶ failed
   └──────abandon_quest()─────┘
                 (repeatable 퀘스트는 completed/failed에서도 start_quest() 재시작 가능)
```

- 데이터베이스에 정의만 된 퀘스트는 **inactive** (저장 파일에도 기록되지 않음)
- `prerequisites`에 적힌 퀘스트가 전부 `completed`여야 시작 가능
- `abandon_quest(id)`: **active** 퀘스트를 포기하고 inactive로 되돌립니다. 목표 진행도는 버려지고 처음부터 다시 시작할 수 있습니다 (완료 이력 `completions`는 보존)
- **completed/failed는 기본적으로 종결 상태**입니다. `repeatable = true`인 퀘스트만 completed/failed에서 `start_quest()`로 재시작 가능 — 목표는 리셋되고 완료 횟수는 누적됩니다
- `get_times_completed(id)`: 누적 완료 횟수 (반복 퀘스트가 아니면 0 또는 1). DSL에서는 `times_completed("daily") < 3` 같은 조건으로 사용

## Objective(목표)

- `NarrativeQuestObjective`: `id`, `description`, `target_count`(최소 1), `initial_count`, `auto_complete_condition`
- `update_objective(quest, objective, delta)`로 카운트 증감 — **[0, target_count]로 클램프**, `completed`는 `count >= target` 자동 반영
- **자동 완료 조건**: `auto_complete_condition`에 조건 DSL(예: `gold >= 100`)을 적으면, 퀘스트가 active인 동안 조건이 참이 되는 순간 해당 목표가 자동 완료됩니다(카운트가 target으로 점프). 평가 시점: 퀘스트 시작 시 + **내러티브 변수가 바뀔 때마다** (외부 상태가 바뀌었으면 `recheck_auto_objectives()` 수동 호출). 한 번 완료된 목표는 조건이 다시 거짓이 되어도 되돌아가지 않습니다
- 목표가 완료되는 순간 `objective_completed(quest_id, objective_id)` 시그널이 방출됩니다 (수동 update든 자동 완료든; `initial_count`로 이미 완료 상태로 시작하는 경우는 제외)
- objective가 모두 완료되어도 **퀘스트는 자동 완료되지 않습니다.** 완료는 항상 명시적 `complete_quest()` — "보고하러 가기"가 기본 흐름이고, 자동 완료를 원하면:
  ```gdscript
  Narrative.quest_updated.connect(func(id):
      if Narrative.are_all_objectives_completed(id):
          Narrative.complete_quest(id))
  ```
- `complete_quest(id)`는 objective 미완료 시 거부됩니다 (`force = true`로 강제 가능)

## 카테고리

`NarrativeQuest.category`는 자유 문자열 그룹 태그입니다 (예: `"main"`, `"side"`, `"daily"`). 런타임은 해석하지 않고 조회 API만 제공합니다:
```gdscript
Narrative.get_quest_category("rat_hunt")            # "side"
Narrative.get_quest_categories()                    # ["daily", "main", "side"]
Narrative.get_quests_in_category("side")            # 카테고리 전체
Narrative.get_quests_in_category("side", "active")  # 상태 필터
```

## 보상

`NarrativeQuest.rewards`는 **액션 DSL 문자열** — 완료 순간 실행:
```
gold += 100
alert("ui.alert.reward_gold")
start_quest("next_chapter")
```
보상이 다른 퀘스트를 완료시키는 연쇄도 가능합니다 (재귀 깊이 8 가드).

## 대화와의 연결 (이 애드온의 핵심)

대화 노드/선택지의 actions·conditions에서 바로:
```
# actions
start_quest("rat_hunt")
update_objective("rat_hunt", "kill_rats", 1)
complete_quest("rat_hunt")
abandon_quest("rat_hunt")

# conditions
quest_state("rat_hunt") == "inactive"
is_quest_active("rat_hunt") and objective_count("rat_hunt", "kill_rats") >= 5
is_quest_completed("rat_hunt")
times_completed("daily_run") < 3
```

게임 코드에서는 파사드로 동일 작업: `Narrative.start_quest(...)`, `Narrative.update_objective(...)` 등 ([api_reference.md](api_reference.md)).

## 중요 설계: 리소스는 절대 변하지 않습니다

`QuestResource`/`ObjectiveResource`의 필드는 **저작 시 초기값**입니다. 런타임 진행 상태(상태, 카운트, 추적 여부)는 첫 시작 시점에 `NarrativeState`로 복사되어 그쪽에서만 변합니다. 따라서:
- 에디터에서 .tres가 오염될 일이 없고
- "새 게임"이 항상 깨끗하게 시작하며
- 저장 파일이 리소스와 독립적입니다

## UI

| 씬 | 역할 | 사용법 |
|---|---|---|
| `ui/quest_log.tscn` | 진행 중(목표·트래커 토글·**Abandon 버튼**)/완료/실패 목록, 반복 완료는 **×N 배지** | 씬에 추가 후 `toggle()` 호출 (또는 `toggle_action` 지정). Abandon 버튼은 `show_abandon_button = false`로 숨김 (문구 키: `ui.quest_log.abandon`) |
| `ui/quest_tracker.tscn` | 추적 중 퀘스트 HUD (비면 자동 숨김) | 씬에 추가만 하면 됨 |

- `auto_track = true`(기본)인 퀘스트는 시작 시 트래커에 표시, 로그의 체크박스로 토글
- 두 UI 모두 `quest_updated`/`language_changed` 시그널로 자동 갱신되며, 다른 디자인이 필요하면 같은 시그널을 구독하는 자체 UI로 교체하면 됩니다

## 퀘스트 시작/완료 알림

UI 강제 없음 — 데모처럼 **대화 액션에서 직접** `alert("ui.alert.quest_started")`를 호출하는 방식을 권장합니다 (`ui/alert_ui.tscn`이 큐로 표시).
