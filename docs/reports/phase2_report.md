# Phase 2. 런타임 코어 (리소스 + DSL + DialogueRunner + 기본 UI)

## 목표
Resource 데이터 모델, 안전 DSL(조건/액션), 상태 관리, 대화 러너, 기준 UI 2종을 구현하고 headless 테스트로 검증한다.

## 구현 내용
- **리소스 10종** (`resources/`): NarrativeDatabase(중복 id 검출 lazy 인덱스), NarrativeSettings, NarrativeCharacter(표정 dict), NarrativeDialogue(노드 인덱스), NarrativeDialogueNode, NarrativeChoice(show_disabled), NarrativeQuest/NarrativeQuestObjective(**초기값 전용** — 런타임 상태는 NarrativeState), NarrativeVariable(타입별 기본값), NarrativeLocalizationTable. 전부 순수 @export 데이터, @tool 없음.
- **DSL** (`runtime/dsl/`): 자체 렉서(위치 보고) → 재귀하강 파서(조건/액션/시퀀서 3 진입점, 조건 모드 대입 금지, 비교 연쇄 거부) → 평가기(순수 evaluate + 파스 캐시 + 경고 1회 + 실패 정책) + 함수 화이트리스트 레지스트리(반환 타입 검사, arity 검사) + 내장 함수 12종.
- **런타임**: NarrativeState(변수 타입 강제, seen/history/current 추적, variable_changed), NarrativeLocalizationManager(3단계 resolve, 관례 키 빌더 — P5에서 CSV 확장), NarrativeContext(DI 허브, alert/bark 시그널, 액터 레지스트리), **NarrativeDialogueRunner**(시그널 8종, 조건 게이트→seen→액션→표시 순서, 홉 가드, 단일 슬롯 펜딩 큐 + 반복 드레인, 언어 변경 시 현재 라인 재표시), autoload 파사드 `narrative.gd`(시그널 재방출 + API 위임).
- **UI**: dialogue_box.tscn(화자/초상화/타자기 효과/계속 표시기, 늦은 부착 시 상태 풀), choice_list.tscn(버튼 생성, 비활성 표시, 포커스).

## 생성/수정 파일
resources/ 10개, runtime/dsl/ 5개, runtime/ 5개(narrative_state, localization_manager, dialogue_runner, narrative_context, narrative.gd), ui/ 4개, tests/ 6개(fixtures/db_factory + test_lexer/parser/conditions/dialogue_runner/ui_basic), .gitattributes.

## 동작 방식
`NarrativeContext.create(db, tree)`가 의존 순서로 서브시스템을 조립(전부 RefCounted, Node는 autoload 파사드뿐). 대화는 start_dialogue → `_enter_node` 루프(조건 false→next 홉)→ 액션 → line_presented/choices_presented → UI가 시그널로 그림. 처리 중 재진입 호출은 큐잉 후 반복 드레인.

## 검증 방법 / 테스트 결과
`--import` 후 headless 러너 실행: **64/64 PASS (0.62s, exit 0)** — 렉서 9, 파서 12, 평가기 17, 러너 16, UI 5, 스모크 5. 재진입 드레인(12노드 자동 진행), 홉 가드(순환), 깨진 링크, 미지 id, 숨김/비활성 선택지, has_seen 첫만남 분기, UI 버튼 생성/선택/늦은 부착까지 전부 자동 검증.

## 발견된 문제 (해결됨 — Godot 4.6.3 실측 지식)
1. **class_name 전역 캐시**: 새 class_name 스크립트는 `--import` 전까지 이름 해석 불가 → 테스트 전 import 필수 (run_tests.ps1이 보장).
2. **메서드 Callable의 약참조**: RefCounted 인스턴스의 메서드 Callable은 대상 객체를 살려두지 않음 → 지역변수로만 만든 내장함수 제공자가 즉시 해제되어 모든 builtin 호출이 invalid. **컨텍스트가 인스턴스를 명시 보유**하도록 수정. (람다는 강참조라 probe 테스트는 통과 — 비대칭 실측 확인)
3. **시그널-람다 캡처 순환**: ctx를 캡처한 람다를 ctx 소유 시그널에 연결하면 RefCounted 순환 → 종료 시 누수. 내부 배선은 WeakRef 람다로, 테스트는 after_each에서 `disconnect_all_signals()`로 해제.

## 남은 한계
- 타자기 효과는 언어 변경 재표시 때 처음부터 다시 재생(MVP 허용).
- 선택지 숫자 단축키 미구현(포커스 네비게이션만, M2).

## 다음 단계
P3 퀘스트: QuestManager(copy-on-first-touch), QuestLog/QuestTracker/AlertUI, 퀘스트 내장 함수 실연결, 리소스 불변성 테스트.
