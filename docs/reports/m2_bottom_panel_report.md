# M2-2 보고서 — 하단 패널 고도화 (미리보기 · 번역 커버리지 · 이슈 포커스)

날짜: 2026-06-11 · 커밋: d4d0580 · 테스트: 237/237 (212 → +25)

## 구현 내용

### 1. Preview 탭 — 에디터 내 대화 재생
- `editor/preview_panel.gd` (신규): 로드된 데이터베이스로 **샌드박스 `NarrativeContext`**를 만들어 대화를 에디터 안에서 재생. 실행마다 컨텍스트를 새로 생성(상태 초기화)하고, 런타임의 "리소스 불변" 계약 덕분에 미리보기가 저작 데이터를 절대 더럽히지 않음.
- 트랜스크립트(RichTextLabel): 화자 이름은 로컬라이즈, `[var=x]` 치환·`[color=…]` 마크업이 실제로 렌더링됨. 선택지는 버튼으로(조건 비활성 포함), Next ▸ 버튼은 러너 단계를 따라 활성/비활성.
- 퀘스트 변화(📜)/알림(🔔)/표정(🎭)을 로그에 기록, 우측에 변수·퀘스트 라이브 상태 트리.
- **시퀀서는 분리**: 🎬 시퀀스 줄은 실행하지 않고 로그로만 표시(에디터엔 씬/액터/타이머가 없음 — 의도된 차이).
- 언어 셀렉터: 실행 중 전환하면 런타임 경로(`language_changed` → 재표현) 그대로 현재 라인/선택지를 새 언어로 다시 표시.

### 2. Localization 탭 — 누락 번역 일괄 표시
- `editor/localization_report.gd` (신규, 헤드리스 코어): 번역 단위(노드/선택지 텍스트, 캐릭터 이름, 퀘스트 제목/설명, objective 설명)마다 키(명시 키 우선, 없으면 컨벤션 키)를 정해 데이터베이스의 모든 로케일(테이블 출현 로케일 + 기본/폴백 언어)에 대해 커버리지를 계산.
- 규칙은 `LocalizationManager.resolve()`와 동일: **기본 언어는 인라인 텍스트로 커버**, 아무것도 저작 안 된 단위(인라인·키 모두 없음)는 스킵.
- `editor/localization_panel.gd` (신규): 로케일 필터, 요약 라벨(완전 번역 n/m · 로케일별 누락 수), Where/Key/Missing 3열 트리.

### 3. 검증·번역 이슈 더블클릭 → 리소스 포커스
- `NarrativeValidator.parse_where()` (신규 static): 검증기가 만드는 `where` 문자열(`dialogue 'x' > node 'y' > choice 'z' > text` 류)을 구조화된 ref로 역파싱. 포맷이 같은 클래스 내부에 있으므로 커플링이 클래스 안에 갇힘 + 실제 이슈 전수 라운드트립 테스트로 고정.
- `NarrativeValidator.resolve_reference()` (신규 static): ref → 실제 리소스(+그래프 포커스용 dialogue/node id).
- `dialogue_graph_editor.focus_node(dialogue_id, node_id := "")` (신규): 대화 열기 + 노드 단일 선택 + 뷰 중앙 정렬.
- `narrative_panel.focus_reference()`: Inspector(`EditorInterface.edit_resource`) + 메인 스크린 전환(`set_main_screen_editor("Narrative")`) + 그래프 점프 라우팅. plugin.gd가 패널↔그래프 에디터를 연결.

### 4. 런타임 코어 @tool 전환
에디터 미리보기가 런타임을 직접 실행해야 하므로 13개 런타임 스크립트에 @tool 추가 (함정 ⑦: 에디터에서 non-@tool 스크립트는 placeholder 인스턴스). @tool은 "에디터에서 실행 가능"일 뿐 게임 동작에는 무영향.

## 테스트 (+25)
- `test_preview_panel.gd` (10): 재생/진행/종료, 선택지 버튼(비활성 포함), 선택 액션 실행, 언어 전환 재표현, 시퀀스 미실행 보장, 퀘스트 로그+상태 트리, 재시작 시 상태 초기화, stop, 리소스 불변.
- `test_localization_report.gd` (7): 로케일 수집, 기본 언어 인라인 커버, 명시/컨벤션 키, 캐릭터/퀘스트/objective 단위, 키 전용 단위의 기본 언어 누락, 미저작 스킵, ref 해석 전수.
- `test_bottom_panel.gd` (3): 검증 더블클릭 → 파싱된 ref 전달, Localization 필터/활성화, focus_reference → 그래프 점프(헤드리스, EditorInterface 가드).
- `test_validator.gd` (+3): parse_where 포맷 전수, 실제 이슈 라운드트립, resolve_reference 대상별.
- `test_graph_editor_ui.gd` (+2): focus_node 전환/단일 선택/중앙 정렬, 미지 대상 처리.

## 결정/메모
- 검증 이슈에 구조화 ref를 "추가 저장"하는 대신 `where` 역파싱을 택함 — 40여 개 호출부 변경 없이 CLI/테스트 출력 포맷 유지. 포맷 변경 시 라운드트립 테스트가 즉시 잡음.
- 미리보기의 시퀀서 실행은 의도적으로 제외(M3-3 인터럽트/액터 미리보기와 함께 재검토).
- 에디터 GUI 수동 검증: computer-use 승인 대기로 보류 — 체크리스트는 본 보고서 하단.

## 수동 검증 체크리스트 (에디터)
- [ ] 하단 패널 4탭(Database/Validation/Localization/Preview) 표시·전환
- [ ] Preview: 데모 DB 대화 재생(라인/선택지/Next), 언어 전환, Stop/재시작
- [ ] Localization: 행 표시, 로케일 필터, 더블클릭 → Inspector+그래프 포커스
- [ ] Validation: 이슈 더블클릭 → 메인 스크린 Narrative 전환 + 노드 선택/중앙 정렬
- [ ] demo_database.tres 저장 안 함(확인 후 git status 클린)
