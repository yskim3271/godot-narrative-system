# 아키텍처 설계 — Narrative System for Godot

## 1. 계층 구조

```
게임 코드 ──(signal/메서드)── Narrative (autoload 파사드, 유일한 Node)
                                 │ 소유
                            NarrativeContext (RefCounted, DI 컨테이너)
                                 ├─ database: NarrativeDatabase (불변 .tres 데이터)
                                 ├─ settings: NarrativeSettings
                                 ├─ state: NarrativeState          ← 런타임 진실의 원천
                                 ├─ evaluator: DSL 평가기(파스 캐시+함수 레지스트리)
                                 ├─ localization: LocalizationManager
                                 ├─ quests: QuestManager
                                 ├─ sequencer: Sequencer
                                 ├─ runner: DialogueRunner
                                 ├─ scene_tree: SceneTree (nullable)
                                 └─ actor_registry: { id → Node }
UI 씬들(DialogueBox/ChoiceList/QuestLog/...) ── signal 구독 전용 (+ setup(context) 오버라이드)
```

핵심 원칙:

1. **Node는 autoload 파사드 하나뿐.** 서브시스템은 전부 RefCounted — 씬 트리 없이(headless) 전체 로직 실행 가능.
2. **파사드는 서브시스템 시그널을 동일 이름으로 재방출.** 게임 코드는 `Narrative.line_presented.connect(...)`만 알면 됨.
3. **테스트/비autoload 사용**: `NarrativeContext.create(db, tree)`로 독립 조립.
4. **리소스 순수성**: `.tres` 리소스는 런타임에 절대 수정하지 않는다. 퀘스트 상태·objective 카운트 등 가변 상태는 첫 접근 시 `NarrativeState`로 복사(copy-on-first-touch). 이유: Godot 리소스는 캐시 공유 인스턴스라 수정하면 (a) 저작 데이터 오염, (b) 에디터에서 .tres 역저장 사고, (c) 새 게임 시작 시 이전 런 상태 잔존.
5. **editor/runtime 분리**: 런타임은 에디터 클래스를 절대 import하지 않음. `validation/`·그래프 모델은 에디터 비의존(headless 테스트/CLI 겸용). **@tool 규칙**: 에디터 코드가 메서드를 호출하는 모든 순수 로직 스크립트(리소스, validator, CSV 도구, DSL 렉서/파서, 그래프 모델)는 `@tool` — 아니면 에디터에서 placeholder 인스턴스가 되어 메서드 호출이 실패한다(4.6.3 실측). 단, 이들 스크립트는 엔진 콜백(_ready 등)·부작용 코드를 갖지 않는다는 전제를 유지한다. 씬 트리 UI/노드(runtime ui, actor 등)는 non-@tool.
6. **명명 동결**: 모든 class_name은 `Narrative*` 접두사(전역 충돌 방지). 스크립트 경로와 클래스명은 공개 API로 취급해 변경 금지.

## 2. 재진입(re-entrancy) 가드

- DialogueRunner는 `_busy` 플래그 + **단일 슬롯 펜딩 큐** 보유. 처리 중(`_busy`) 들어온 `advance()/select_choice()`는 큐잉, 같은 트랜지션에서 두 번째 큐잉은 경고+드롭. 드레인은 반복문(자동 진행 대화도 스택 증가 없음).
- 처리 중 `start_dialogue()` 호출 = 에러+거부 (MVP는 인터럽트 스택 없음 — `end_dialogue()` 먼저).
- 퀘스트 보상 액션의 재귀(`complete_quest` 연쇄)는 깊이 8 제한.
- 처리 중 `save_game()` = `ERR_BUSY` (라인/선택지 대기 중 저장은 항상 안전).

## 3. 노드 진입 순서 (`_enter_node`)

```
seen/history 기록 → node_entered 방출
→ 노드 조건 평가: false면 next_node_id로 홉 (max_node_hops=64 가드)
→ 액션 실행 (variable_changed / quest_updated 동기 방출)
→ 텍스트 해석(로컬라이징 3단계) + 선택지 조건 평가
→ phase 설정 (AT_LINE | AT_CHOICES)
→ line_presented 방출 → (선택지 있으면) choices_presented 방출
→ 시퀀서 런 시작 (비대기, run-id 토큰으로 취소 가능)
```

시퀀스는 **대사 표시와 병행** 실행된다(카메라 연출이 대사를 막지 않도록). `advance()/select_choice()`가 진행 중 시퀀스를 취소한다.

## 4. 저장/복원 흐름

- SaveManager는 `NarrativeState` ↔ JSON 순수 변환만 담당.
- 복원 시 대화 재개(try_resume)는 **표현만 재생**: 텍스트 재해석+선택지 재평가+`dialogue_resumed` 방출. 액션/시퀀서는 재실행하지 않음(효과는 이미 저장된 변수/퀘스트에 반영되어 있음).
- 저장 후 데이터베이스가 변경되어 대상 노드가 없으면 경고+current 폐기(크래시 없음).

## 5. 디렉토리 구조

`addons/narrative_system/` 아래: `runtime/`(+`dsl/`), `resources/`, `ui/`, `editor/`, `validation/`, `import_export/`, `tests/`. 데모는 `examples/integrated_demo/`, 문서는 `docs/`. 전체 트리는 저장소 루트 README 참고.

## 6. 테스트 전략

- 자체 경량 하니스(`tests/run_tests.gd`, SceneTree 스크립트) — 외부 프레임워크 비의존.
- 실행: `godot(_console).exe --headless --path . -s res://addons/narrative_system/tests/run_tests.gd [-- --filter=...]`
- 테스트 DB는 `tests/fixtures/db_factory.gd`가 코드로 생성(.tres 픽스처 금지 — 클래스 변경 시 썩음).
- 타이밍 주의(실측): 첫 프레임 delta에 부팅 시간이 포함 → 러너가 시작 전 2프레임 펌프, 각 테스트를 프레임 경계에서 시작. SceneTreeTimer는 프레임 양자화로 wall-clock 기준 최대 1프레임 조기 발화 가능 — 타이밍 어서션은 여유 하한 사용.
