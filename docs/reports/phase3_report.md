# Phase 3. 퀘스트 시스템 + QuestLog/QuestTracker/Alert UI

## 목표
대화와 직결되는 퀘스트 라이프사이클(inactive→active→completed/failed)과 로그/트래커/알림 UI를 구현하고, 리소스 불변성을 보장한다.

## 구현 내용
- **NarrativeQuestManager** (`runtime/quest_manager.gd`): start(선행조건 검사)/complete(objective 완료 요구, force 오버라이드)/fail/update_objective(0~target 클램프, completed=count≥target 자동 반영)/set_tracked. 런타임 상태는 전부 `NarrativeState.quest_states`에 copy-on-first-touch — **리소스 무변경**. 보상은 액션 DSL로 완료 시 실행(재귀 깊이 8 가드). 미지 id는 1회 경고 + "inactive". 로컬라이즈된 제목/설명/objective 진행 조회 헬퍼 제공.
- **퀘스트 DSL 내장 함수 실연결**: `start_quest/complete_quest/fail_quest/update_objective/quest_state/is_quest_*` — 대화 노드 액션에서 바로 사용 가능 (P2의 스텁이 실제 매니저로 연결됨).
- **UI 3종**: `quest_log.tscn`(활성/완료/실패 섹션, objective 진행, 트래커 토글 체크박스, 열려 있을 때 자동 갱신 — deferred+dirty 패턴으로 시그널 핸들러 중 자기 재구축 방지), `quest_tracker.tscn`(추적 중 퀘스트 HUD, 비면 자동 숨김), `alert_ui.tscn`(큐잉 토스트, 표시→페이드→다음).
- **파사드 확장**: 퀘스트 API 15종 위임 + `get_ui_text(key, fallback)`(UI 문구 로컬라이징 도그푸딩).

## 생성/수정 파일
runtime/quest_manager.gd(신규), ui/quest_log·quest_tracker·alert_ui(.gd+.tscn 6개 신규), runtime/narrative_context.gd(quests 배선), runtime/narrative.gd(퀘스트 위임), runtime/localization_manager.gd(text_or), tests/fixtures/db_factory.gd(퀘스트 6종+questgiver 대화), tests/test_quest_manager.gd(11), tests/test_quest_ui.gd(5).

## 동작 방식
대화 액션 `start_quest("rats")` → 매니저가 리소스 초기값을 NarrativeState로 복사 후 active + `quest_updated` 방출 → QuestLog/Tracker가 deferred 갱신. 완료 시 rewards DSL 실행(`gold += 100; alert(...)`) → alert_requested → AlertUI 큐.

## 검증 방법 / 테스트 결과
headless 전체: **80/80 PASS (1.29s, exit 0)**. 신규 16개: 시작/시그널, 선행조건 차단, 클램프+완료 플래그(감소 시 역전 포함), 완료 거부/강제, 실패 상태 전이, 미지 id 5종 무크래시, 보상 체인(chain_a 완료→chain_b 자동 완료), **대화 액션 경유 시작+조건 분기**, 추적 토글/목록, **리소스 불변성 스냅샷 검증**, 트래커 진행 표시/완료 시 제거, 로그 섹션/열린 상태 갱신, 알림 큐 진행/소진, 파사드 위임.

## 발견된 문제
- 로그 UI가 quest_updated 핸들러 안에서 자기 자신을 재구축하면 방출 중인 체크박스를 해제하는 문제 → deferred+dirty 갱신 패턴으로 설계 단계에서 회피 (테스트는 await frame으로 정합).
- 한계: objective 자동 완료 시 퀘스트 자동 완료는 의도적으로 미지원(명시적 complete_quest) — `are_all_objectives_completed()` 헬퍼로 게임이 결정. known_limitations에 기록 예정.

## 다음 단계
P4 Save/Load: 버전드 JSON 스냅샷(원자적 쓰기/격리/마이그레이션), runner try_resume(표현만 재생), 결정적 저장 검증.
