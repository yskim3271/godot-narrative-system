# Changelog

## 1.2.0 (2026-06-11)

### 추가
- **에디터 하단 패널 고도화 (M2-2)** — 탭 4종으로 확장:
  - **Preview**: 에디터 안에서 대화 재생(샌드박스 컨텍스트 — 실행마다 fresh 상태, 리소스 불변). 로컬라이즈 화자·`[var=x]`/BBCode 렌더링·선택지 버튼(조건 비활성 포함)·퀘스트 📜/목표 🎯/알림 🔔 트랜스크립트·변수/퀘스트 라이브 상태 트리·실행 중 언어 전환. 시퀀서 줄은 실행하지 않고 🎬 로그로만 표시.
  - **Localization**: 전 번역 단위(노드/선택지/캐릭터/퀘스트/objective)의 로케일별 누락 리포트(기본 언어는 인라인 텍스트로 커버 — `resolve()` 패리티), 로케일 필터.
  - **이슈 더블클릭 → 포커스**: Validation/Localization 행 더블클릭 시 메인 스크린 그래프가 해당 노드를 선택+중앙 정렬하고 Inspector에 리소스를 엶 (`NarrativeValidator.parse_where()/resolve_reference()`, 그래프 `focus_node()`).
- **퀘스트 고도화 (M3-2)**: `abandon_quest()`(active→inactive, 완료 이력 보존), **반복 퀘스트**(`repeatable` — completed/failed에서 재시작, 완료 횟수 누적, `get_times_completed()`), **objective 자동 완료 조건**(`auto_complete_condition` — 변수 변경 시 평가, `objective_completed` 시그널), **카테고리**(`category` + 조회 API). DSL `abandon_quest()`/`times_completed()` 추가.
- **QuestLog UI**: 진행 중 퀘스트에 Abandon 버튼(`show_abandon_button`, 문구 키 `ui.quest_log.abandon`), 반복 완료 ×N 배지.
- 런타임 코어 전체 `@tool` 전환(에디터 미리보기용 — 게임 동작 무영향).

### 변경
- **저장 스키마 v2** (`SAVE_VERSION = 2`): 퀘스트 항목에 `completions` 추가, abandon된 퀘스트의 `"state": "inactive"` 항목 허용. **v1 저장은 1→2 마이그레이션으로 자동 호환**(completions 백필). (docs/save_format.md)

## 1.1.0 (2026-06-11)

### 추가
- **그래프 에디터 인라인 편집**: 노드 화자·텍스트·**선택지 텍스트/타깃**을 캔버스에서 직접 편집(포커스 이탈 시 1 undo 단위로 커밋). 헤더의 id 칸으로 **노드 rename** 시 그 id를 가리키던 next/choice 링크와 `start_node_id`를 전부 자동 추적(`rename_node`). 타깃 칸은 포트 드래그·undo와 양방향 동기. 전부 Ctrl+Z/Y 대응. (docs/graph_editor.md)
- **인라인 마크업 `[var=x]`**: 대사/선택지/바크/알림 텍스트에서 내러티브 변수 치환(로컬라이징 해석 후 적용, 미선언 변수는 원문 유지 + 검증기 `markup_unknown_variable` 경고). BBCode는 통과. 에디터 단축키 — Ctrl+Shift+V(`[var=…]` 삽입)/Ctrl+Shift+C(`[color]` 감싸기), 선택지 자동 넘버링(툴바 1.2.3 / Ctrl+Shift+N, 토글). (docs/dialogue_authoring.md)
- **시퀀서 병렬 스케줄링 + 메시지 동기화** (Unity DS 패리티): `cmd() @ 2.5`(런 시작 기준 병렬), `cmd() @ message("name")`(대기), `cmd() -> "name"`(완료 시 브로드캐스트, 스킵돼도 발생 — 데드락 방지). `run_finished`는 전 작업 완료 시. `Narrative.send_sequencer_message()` + `sequencer_message` 시그널. 장식 없는 줄은 기존 순차 동작 그대로. (docs/sequencer.md)
- **3D 지원**: `move_camera_3d(x,y,z[,d])`, 3D 액터 `focus_camera`(제자리 회전 주시), BarkUI 3D 말풍선(화면 공간 투영 추적).
- **Asset Library 패키징**: `.gitattributes` export-ignore로 배포 zip을 `addons/narrative_system/`만으로 구성, 영문 패키지 README, 제출 체크리스트(docs/asset_library_submission.md).

### 수정
- **그래프 에디터가 실제 에디터 메인스크린에서 빈 캔버스로 표시되던 출하 1.0.0 결함**: 메인스크린은 Container라 anchors를 무시하는데 `EXPAND_FILL`이 없어 GraphEdit 높이가 0이 됨 → size flags 추가. headless 수동 확인에서 발견, 회귀 테스트 추가.
- `NarrativeDialogue.invalidate_index()`: in-place 노드 id 변경(rename) 시 size 기반 자동 재빌드가 놓치던 스테일 노드 인덱스(1.0.0의 DB 레벨 `invalidate_indexes()`에 대응하는 대화 레벨 수정).

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
