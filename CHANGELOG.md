# Changelog

## 0.1.0 (2026-06-11) — MVP

첫 릴리스. Godot 4.4+ (4.6.3에서 개발·검증).

### 추가
- **데이터 모델**: NarrativeDatabase + Character/Dialogue/DialogueNode/Choice/Quest/QuestObjective/Variable/LocalizationTable/Settings 리소스 (런타임 불변, 중복 id 검출)
- **안전 DSL**: 자체 렉서/파서/평가기 (조건식·액션문·시퀀서 명령), 함수 화이트리스트 레지스트리, 내장 함수 13종 (`has_seen`, `quest_state`, `objective_count`, `start_quest`, `alert` …)
- **DialogueRunner**: 분기/조건 스킵(홉 가드)/선택지(숨김·비활성)/재진입 안전 큐/seen 추적/언어 변경 재표시
- **QuestManager**: inactive→active→completed/failed, 선행조건, objective 클램프, 보상 액션(재귀 가드), copy-on-first-touch 런타임 상태
- **SaveManager**: 버전드 JSON(user://saves), 원자적 쓰기+백업 회전, 손상 격리, 마이그레이션 체인, 대화 위치 재개(표현만 재생), 적대적 데이터 방어
- **LocalizationManager**: 계층 해석(현재 언어 → 인라인(기본 언어) → 폴백 언어), 관례 키, 누락 키 수집, CSV import/export(BOM 처리), 런타임 언어 전환
- **Sequencer**: 취소 가능한 순차 런, 내장 명령 15종, 커스텀 명령 등록, NarrativeActor 액터 레지스트리
- **UI 7종**(레퍼런스): DialogueBox(타자기), ChoiceList, QuestLog, QuestTracker, AlertUI(큐), BarkUI(말풍선), 전부 재바인딩 가능
- **에디터**: 플러그인(autoload/설정 등록), 하단 패널(DB 개요/검증/CSV), NarrativeValidator(구조+DSL 정적 분석 20여 종) + headless CLI
- **통합 데모**(한국어 기본/영어 전환) + 테스트 137개 + 검증 파이프라인(run_tests.ps1)
