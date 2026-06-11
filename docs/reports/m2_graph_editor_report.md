# M2. 대화 그래프 에디터 (0.2.0-dev)

## 목표
GraphEdit 기반 노드 그래프 에디터(보기/추가/연결/삭제/시작 지정/배치 저장)를 메인 스크린 탭으로 제공하고, 편집 로직을 headless 테스트로 고정한다.

## 구현 내용
- **`editor/dialogue_graph_model.gd`** (순수 로직, UI/에디터 비의존): 노드 추가(자동 id, 빈 대화 첫 노드=시작), 삭제(**해당 노드를 가리키는 next/choice 링크 전부 자동 정리** + 시작 노드 처리), next/choice 연결·해제(존재 검증), 시작 지정, 연결 목록(포트 계약: 0=next, 1..N=choice), **BFS 자동 배치**(깊이=열/분기=행, 미도달 노드는 마지막 열), 위치 영속(`metadata.graph_position` — .tres 왕복 검증), 새 대화 생성(start 노드 포함), id 생성/검증.
- **`editor/dialogue_graph_editor.gd`** (@tool GraphEdit 셸, **headless 인스턴스 가능** — EditorInterface는 전부 is_editor_hint 가드): 노드 시각화(제목=id, `▶` 시작 표시, 화자+❓⚡🎬 배지, 본문 미리보기, 선택지별 노랑 출력 포트), 드래그 연결/해제, 우클릭 Add Node Here, Del/툴바 삭제, Set Start, 노드 선택→Inspector 열기, 이동 종료 시 위치 기록, Save(위치 영속+ResourceSaver), Validate 요약, 대화 선택 드롭다운/New Dialogue 다이얼로그, Refresh.
- **plugin.gd 메인 스크린 통합**: `_has_main_screen`/`_get_plugin_name("Narrative")`/아이콘/`_make_visible`(재진입 시 refresh — 같은 캐시 인스턴스라 Inspector 편집이 무손실 반영).

## 발견된 문제 (해결됨)
1. 테스트 파일에서 함수 내부 `const` 선언(GDScript 불법) → 파일 파스 실패. 무결성 게이트가 8건 전부 실패로 표면화 → 파일 스코프로 이동.
2. `_ellipsis()` 헬퍼 미정의 호출 → 추가.
3. **에디터 placeholder 인스턴스 버그(중요)**: non-@tool 스크립트의 리소스는 에디터에서 placeholder가 되어 **메서드 호출이 실패** — P8의 database_path 설정으로 패널/그래프가 자동 로드를 시작하자 표면화됐고, **P7 Validate 버튼도 같은 잠복 버그**였음(headless 스모크는 버튼을 누르지 않아 미검출). 원칙 정정: "에디터가 메서드를 호출하는 순수 로직 스크립트는 전부 @tool"(엔진 콜백 없음 전제 유지) — 리소스 10종, validator, CSV 도구, DSL 렉서/파서, 그래프 모델 16개 파일 적용. architecture.md 원칙 갱신.

## 생성/수정 파일
editor/dialogue_graph_model.gd·dialogue_graph_editor.gd·icons/narrative_main.svg(신규), plugin.gd(메인 스크린), tests/test_graph_model.gd(12)·test_graph_editor_ui.gd(8), @tool 16파일, docs/graph_editor.md(신규), README/known_limitations/roadmap/CHANGELOG/test_report/architecture(갱신), version 0.2.0-dev.

## 검증 방법 / 테스트 결과
- 전체 파이프라인 **ALL GREEN**: 유닛 **157/157 (4.7s, SCRIPT ERROR 0)** · 해피패스 순수성 클린 · 데모 DB strict 0/0
- **에디터 headless 스모크**: 메인 스크린 플러그인 + 패널/그래프 자동 로드 포함 → exit 0, **SCRIPT ERROR 0** (@tool 수정 전 4건 → 0건)
- 모델 12종: 참조 정리 카운트, 시작 노드 삭제 처리, 경계(인덱스/미지 id/중복/문자셋), 자동 배치 결정성·무중첩·재실행 무변경, .tres 위치 왕복
- UI 8종: 포트 배선(헤더 in/next out, 미리보기 무포트, 선택지별 out), 연결 교체 의미론, 해제, 추가/삭제(그래프·데이터 동기), 시작 표시, 이동 영속, 대화 전환, 실패한 열기에 기존 상태 유지

## 남은 한계 (graph_editor.md·known_limitations에 문서화)
- undo/redo 없음(다음 후속 1순위 — EditorUndoRedoManager), 필드 인라인 편집은 Inspector 경유, Inspector 구조 변경 후 Refresh 필요, 노드 id rename 시 링크 자동 추적 없음.
- 실제 에디터에서의 시각/조작감(드래그 UX, 포트 히트박스)은 headless로 검증 불가 — ▶ 에디터에서 Narrative 탭 수동 확인 권장.

## 다음 단계 (제안)
M2 후속: ① EditorUndoRedoManager 통합 ② 인라인 텍스트/화자 편집 ③ 검증 이슈 더블클릭→그래프 노드 포커스. 또는 사용자 우선순위에 따라 M3/배포 준비로 전환.
