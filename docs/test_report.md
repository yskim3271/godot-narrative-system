# 테스트 결과 보고서 (1.0.0)

검증 환경: Godot 4.6.3-stable (win64 console 빌드), Windows 11 · 2026-06-11

## 최종 결과 (`.\scripts\run_tests.ps1` 5단계 집계)

| 단계 | 내용 | 결과 |
|---|---|---|
| 1 | `--import` (클래스 캐시/에셋) | ✅ exit 0 |
| 2 | 유닛/통합 테스트 (19 파일) | ✅ **174/174 PASS**, ~5.0s, SCRIPT ERROR 0 |
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
| test_graph_editor_ui | 8 | GraphEdit 셸: 포트 배선·연결/해제/삭제 제스처·시작 표시·위치 영속 |
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

## 수동 확인 권장 항목

1. 에디터에서 플러그인 체크박스 토글 → autoload 등록/해제 확인 (headless 자동화 불가 경로)
2. 데모 ▶ 실행 후 README의 체험 순서 8단계 (시각/입력 경험)
3. 하단 Narrative 패널에서 데모 DB Load → Validate → CSV Export/Import
