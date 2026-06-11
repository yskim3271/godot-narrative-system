# 테스트 결과 보고서 (1.0.0)

검증 환경: Godot 4.6.3-stable (win64 console 빌드), Windows 11 · 2026-06-11

## 최종 결과 (`.\scripts\run_tests.ps1` 5단계 집계)

| 단계 | 내용 | 결과 |
|---|---|---|
| 1 | `--import` (클래스 캐시/에셋) | ✅ exit 0 |
| 2 | 유닛/통합 테스트 (19 파일) | ✅ **175/175 PASS**, ~5.0s, SCRIPT ERROR 0 |
| 3 | 해피패스 순수성 게이트 (통합 플로우 출력에 엔진 ERROR/WARNING 0) | ✅ clean |
| 4 | 데모 DB 정적 검증 (`validate_cli --strict`) | ✅ 0 error / 0 warning |
| 5 | **데모 씬 5종 headless 부팅** (30프레임, SCRIPT ERROR 0) | ✅ 5/5 |
| 부가 | 에디터 headless 스모크 (`--headless --editor --quit`) | ✅ exit 0, 에러 0 |

재현: `.\scripts\run_tests.ps1` (전체 4단계 집계 exit code)

## 커버리지 (파일별)

| 파일 | 수 | 검증 내용 |
|---|---|---|
| test_smoke | 5 | 하니스 자체(격리/비동기/레코더) |
| test_lexer | 9 | 토큰화·이스케이프·위치 보고·모드별 개행 |
| test_parser | 12 | 우선순위·AST 형태·거부 규칙(`=`/연쇄 비교/키워드)·기형 입력 8종 |
| test_conditions | 17 | 타입 의미론·단락 평가·실패 정책·함수 등록/arity·캐시·시그널 |
| test_dialogue_runner | 16 | 분기·스킵·홉 가드·재진입 큐·숨김/비활성·seen·미지 id |
| test_quest_manager | 11 | 전이·선행조건·클램프·보상 체인·**리소스 불변성** |
| test_quest_ui | 5 | 트래커/로그/알림 큐 + 파사드 |
| test_ui_basic | 5 | 대화창/선택지 UI 헤드리스 |
| test_save_load | 12 | 왕복·재개(액션 미재실행)·격리·버전·마이그레이션·원자성·결정성 |
| test_save_hardening | 6 | 적대적 데이터(타입 오염/잘림/재클램프/레거시) |
| test_localization | 9 | 계층 해석·인라인 우선·누락 수집·CSV 한글/BOM·전환 재표시 |
| test_sequencer | 12 | wait/취소/명령 15종 경로/커스텀 등록/바크 |
| test_validator | 13 | 검사 전 종류 + **클린 DB 0건 보장** |
| test_demo_database | 4 | 출하 데모 DB 상시 검증 + 콘텐츠 플로우 |
| test_integration_flow | 1 | 종단: 수주→중간 저장→새 컨텍스트 로드→재개→완료→언어→왕복 |
| test_graph_model | 12 | 그래프 편집 모델: 추가/삭제(참조 정리)/연결/시작/자동 배치/.tres 위치 왕복 |
| test_graph_editor_ui | 9 | GraphEdit 셸: 포트 배선·연결/해제/삭제 제스처·시작 표시·위치 영속·**Container 부모 채움(EXPAND_FILL 회귀)** |
| test_graph_undo | 6 | undo/redo: 추가·삭제(링크/시작 복원)·연결 재배선·이동, 무변화 제스처 무기록 |
| test_script_parser | 11 | .ndlg: 문법 전체·부착 규칙·줄 번호 에러·원자적 임포트·교체/스킵·**왕복**·런타임 재생 |

## 스펙 §12 검증 기준 대응

- **기능**: 대화 시작/종료·선택지 분기·조건 표시/숨김·변수 변경·대화 중 퀘스트 시작·objective 갱신·완료·로그/트래커 반영·대화/퀘스트 상태 저장복원·한/영·누락 키 검출·대사 중 애니/오디오/signal — 전부 자동 테스트로 커버 (위 표)
- **안정성**: 미지 dialogue/node/quest/character id, 잘못된 조건식, 잘못된 저장 파일, 순환 그래프, 누락 로컬라이징 키 — 전용 테스트 + 검증기
- **사용성**: 플러그인 enable/disable(에디터 스모크+수동), 샘플 실행(headless 부팅+수동 ▶), README 기반 재현(getting_started 단계 그대로)

## 테스트 인프라 특징

- 외부 프레임워크 없음 — `tests/run_tests.gd`(SceneTree) + 어서션 누적 베이스
- **무결성 게이트**: 어서션 0개로 끝난 테스트는 실패 처리 (GDScript 에러로 중단된 코루틴의 거짓 PASS 차단 — 실제로 P6에서 가짜 12/12를 적발)
- 프레임 경계 정렬로 타이머 결정성 확보(부팅 delta·동기 작업 선입금 보정)
- 픽스처는 전부 코드 생성(`db_factory.gd`) — 클래스 변경 시 컴파일 에러로 즉시 발견

## 수동 확인 결과 (2026-06-11, Godot 4.6.3 에디터 GUI + computer-use)

headless로 검증 불가능한 경로를 에디터를 직접 띄워 확인. 결과 전부 통과:

1. **플러그인 토글**: 체크박스 OFF → `Narrative` autoload가 project.godot·에디터 오토로드 목록·메인스크린 탭·하단 패널에서 모두 제거됨. ON → autoload(UID 형식으로 재기록)·탭·패널 전부 복원. ✅
2. **그래프 에디터(메인스크린 "Narrative" 탭)**: guard_talk 열기, 노드 드래그(선택 시 인스펙터 연동)·Ctrl+Z/Ctrl+Y(이동/Set Start/삭제 전부 undo·redo)·Set Start(▶ 이동)·Del 삭제(+undo 시 링크 복원)·Save(노드 위치를 .tres에 기록). ✅ — 포트 연결/해제 데이터 로직은 헤드리스 3종 + 시각 렌더링으로 확인.
3. **하단 Narrative 패널**: Load(프로젝트 설정에서 자동 로드)·Validate(0 error, "No issues found")·Export CSV(파일 기록 확인)·Import Script(branching.ndlg → "1 new, 0 replaced, saved"). ✅
4. **데모 5종**: integrated(8단계 전부: 분기·조건/비활성 선택지·퀘스트+컷신(set_expression)·트래커/로그·objective 진행·보상(30→130골드)·**선택지 화면 한가운데 F5/F9 복원**·K 즉시 한↔영·bark 순환)·basic(선형 대화)·branching(첫만남 변형·숨김/비활성 선택지·구매 액션·메뉴 루프)·localization_cutscene(K 전환·시퀀서 컷신·카메라 복귀)·quest(수주·objective 0/3→3/3 자동완료·월드 파생). ✅

### 발견·수정한 버그

- **그래프 에디터가 실제 에디터 메인스크린에서 빈 캔버스로 표시됨 (출하 1.0.0 결함)**: 에디터 메인스크린은 Container(VBoxContainer)라 자식 크기를 size flags로 정하고 anchors를 무시하는데, 그래프 에디터는 `PRESET_FULL_RECT` anchors만 설정하고 `EXPAND_FILL`을 두지 않아 최소 높이로 접혀 GraphEdit 높이가 0 → 노드 전부 비가시. 헤드리스 테스트는 비-Container 부모(`scene_tree.root`)에 붙여서 검출 못 함. → `size_flags = EXPAND_FILL` 추가, Container 부모 회귀 테스트 추가. (커밋: graph editor empty-canvas fix)
