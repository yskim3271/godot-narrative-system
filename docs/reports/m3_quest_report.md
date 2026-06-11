# M3-2 보고서 — 퀘스트 고도화 (abandon · 반복 · 자동 완료 · 카테고리)

날짜: 2026-06-11 · 테스트: 248/248 (237 → +11)

## 구현 내용

### 1. abandon_quest
- `abandon_quest(id)`: **active → inactive**. objective 진행도는 폐기, 같은 퀘스트를 처음부터 재시작 가능.
- 완료 이력이 있는 퀘스트(반복 퀘스트 재도전 중 포기)는 `{"state": "inactive", completions}` 항목을 **명시적으로 보존** — "quest_states 부재 = inactive" 불변식에 한 가지 예외를 추가하고 `get_quests_in_state("inactive")`를 `get_quest_state()` 기반으로 재정의해 일관성 유지.

### 2. 반복 퀘스트 (repeatable)
- `NarrativeQuest.repeatable` (기본 false): completed/**failed**에서 `start_quest()` 재시작 허용. 재시작 시 objective 리셋, `completions`(완료 횟수)는 누적.
- `get_times_completed(id)` 매니저/파사드 API + DSL `times_completed(id)` — `times_completed("daily") < 3` 같은 조건 저작 가능. DSL `abandon_quest(id)`도 추가.

### 3. objective 자동 완료 조건
- `NarrativeQuestObjective.auto_complete_condition` (조건 DSL, 예: `gold >= 100`).
- 평가 시점: 퀘스트 시작 직후 + `NarrativeState.variable_changed`마다 (퀘스트 매니저가 setup에서 구독 — 함정 ② 의미론상 메서드 Callable은 약참조라 순환 없음). 외부 상태 변화는 `recheck_auto_objectives()` 수동 호출.
- 참이 되는 순간 count가 target으로 점프하고 완료 고정(조건이 다시 거짓이 돼도 유지). 퀘스트 완료는 여전히 명시적 `complete_quest()` (기존 설계 유지).
- 신규 시그널 `objective_completed(quest_id, objective_id)` — 수동 update가 target에 도달할 때도 방출 (initial_count로 시작부터 완료인 경우는 제외). 파사드 재방출 포함.

### 4. 카테고리
- `NarrativeQuest.category` 자유 문자열 태그 + `get_quest_category` / `get_categories` / `get_quests_in_category(category, state := "")` (런타임은 해석하지 않음, 조회만).

### 5. 저장 스키마 v2 (+ 마이그레이션)
- `SAVE_VERSION 1 → 2`: 퀘스트 항목에 `completions` 추가, `"inactive"` 상태 항목 허용(`VALID_QUEST_STATES`에 추가).
- 마이그레이션 1→2: 모든 퀘스트 항목에 `completions: 0` 백필. sanitize는 음수 completions를 0으로 클램프.
- `docs/save_format.md`에 스키마 이력 표 추가.

### 6. 검증기
- `auto_complete_condition`을 조건 DSL로 정적 검사(파스 에러/미선언 변수/미지 함수 — where: `quest 'q' > objective 'o' > auto_complete`).
- `BUILTIN_FUNCTIONS`/`QUEST_ID_FUNCTIONS`에 `abandon_quest`, `times_completed` 등록(리터럴 quest id 존재 검사 포함).

## 테스트 (+11)
- `test_quest_manager.gd` (+8): abandon 전이/재시작/비active 거부, 완료 이력 보존, repeatable 재시작·완료 횟수·failed 재도전, 변수 변경 자동 완료(+시그널 인자), 시작 시점 자동 완료, 수동 진행 objective_completed(재교차 포함), 카테고리 조회 전수, DSL abandon/times_completed.
- `test_save_load.gd` (+3): v1 저장 → 1→2 마이그레이션 로드(completions 백필), completions·abandoned-inactive 항목 라운드트립, 음수 completions 클램프.
- 기존 212+25개 전부 그대로 통과 — 해피패스 순수성/데모 DB strict/데모 5종 부팅 포함 ALL GREEN.

## 결정/메모
- failed 반복 퀘스트의 재시작을 허용(데일리 퀘스트 재도전 시나리오). 비반복 퀘스트의 completed/failed는 기존대로 종결.
- 퀘스트 레벨 자동 완료(모든 objective 완료 시 자동 complete_quest)는 추가하지 않음 — "보고하러 가기" 기본 흐름 유지, 자동화는 한 줄 시그널 글루로 충분(quest_system.md 예시).
- QuestLog UI에 abandon 버튼/카테고리 그룹핑은 보류 — 런타임 API가 먼저, UI는 후속(M3-3 인터럽트와 함께 UI 패스 검토).
