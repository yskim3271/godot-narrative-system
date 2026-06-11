# Changelog

## 1.0.0 (2026-06-11) — 개발 완료

원 스펙의 필수 기능 20종 전부 구현·검증 완료. (의도적 유예: Yarn/Ink 임포터, C# 전용 API, `@time` 병렬 시퀀서, 에셋 라이브러리 패키징 — roadmap.md)

### 추가
- **그래프 에디터 undo/redo**: 노드 추가/삭제(링크·시작 노드 완전 복원)/연결·재배선·해제/시작 지정/이동 전부 에디터 히스토리(Ctrl+Z) 통합. 무변화 제스처는 히스토리 미오염.
- **텍스트 대화 저작 포맷(.ndlg)**: 라인 기반 작가 친화 문법, 줄 번호 에러 보고, **원자적 임포트**(에러 시 DB 무변경), 제자리 교체/건너뛰기, **왕복 익스포트**(출하 데모 대화로 검증), 패널 Import Script 버튼.
- **샘플 4종 추가** (각 README 포함): basic_dialogue(최소 구성) / branching_choice(**.ndlg로 저작**) / quest(수주→진행→완료) / localization_cutscene(한영 전환+컷신+bark). 통합 데모 포함 총 5종, 전부 파이프라인에서 headless 부팅 검증.

### 수정
- `load_database()`가 액터 레지스트리를 새 컨텍스트로 이월 (씬 `_ready`에서 DB를 교체해도 NarrativeActor 등록 유지)
- `NarrativeDatabase.invalidate_indexes()` — 제자리 교체 시 스테일 id 인덱스 문제

## 0.2.0-dev

### 추가
- **대화 그래프 에디터** (메인 스크린 "Narrative" 탭): 노드 시각화(화자/배지/선택지별 출력 포트), 드래그 연결/해제(next·choice), 우클릭 노드 추가, Del 삭제(참조 자동 정리), 시작 노드 지정, BFS 자동 배치, 위치 영속화(metadata), 새 대화 생성, 저장/검증 버튼. 로직은 `dialogue_graph_model.gd`로 분리되어 headless 테스트 20종으로 고정.

### 수정
- **에디터 placeholder 인스턴스 버그**: 에디터가 접근하는 순수 로직 스크립트(리소스 10종, validator, CSV 도구, DSL 렉서/파서, 그래프 모델)가 non-@tool이어서 에디터에서 메서드 호출이 실패하던 문제(P7 Validate 버튼의 잠복 버그 포함) — 전부 `@tool` 지정(엔진 콜백 없는 순수 코드라 부작용 없음).

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
