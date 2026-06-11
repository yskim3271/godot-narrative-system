# Phase 8. 통합 데모 (examples/integrated_demo)

## 목표
전 MVP 기능을 한 씬에서 시연하는 한국어 기본/영어 전환 데모를 만들고, 데모 데이터가 영구히 깨지지 않도록 테스트로 고정한다.

## 구현 내용
- **데모 데이터베이스**: `db_builder.gd`(코드 저작, 단일 진실원) → `regenerate_db.gd`로 `demo_database.tres` 생성(생성 시 validator 게이트 — 에러면 저장 거부). 내용: 경비병 캐릭터(GradientTexture2D 초상화+happy/angry 표정), 변수(gold=30, met_guard), 쥐 사냥 퀘스트(목표 5, 보상 100골드+알림), **7노드 분기 대화**(첫만남/재방문 인사 변형 패턴, 5개 선택지: 퀘스트 수주/진행 보고/완료 보고(`objective_count` 조건)/뇌물(50골드, 비활성 표시)/작별), 시퀀서 컷신(표정→애니메이션→카메라 팬→signal→카메라 복귀), en 번역+이중 언어 UI/bark 문자열 31키.
- **데모 씬**: `demo.tscn`/`demo.gd` — 이동(방향키)+E 대화, J 로그, K 언어, F5/F9 저장/로드, 쥐 5마리(가시성을 objective 진행에서 **파생** — 저장/로드와 자동 정합), 4초 주기 bark, 골드 HUD, UI 7종 인스턴스, NarrativeActor+AnimationPlayer(wave). project.godot: main_scene/autoload/database_path 배선.
- **계획에 없던 교정 2건**:
  1. **로컬라이징 해석 순서 결함 수정**: 인라인 텍스트(=기본 언어)가 fallback **언어** 테이블보다 우선하도록 변경 — ko 기본+en 번역 구조에서 ko 사용자에게 en이 노출되던 문제. 키 전용 콘텐츠(ui.*)는 기존대로 언어 폴백.
  2. **`objective_count(quest, obj)` DSL 내장 함수 추가**(진행도 조건 분기용) + validator 리터럴 검증 연동.

## 생성/수정 파일
examples/integrated_demo/ 5개(builder/재생성 스크립트/씬/스크립트/README + 생성된 .tres), runtime/localization_manager.gd(해석 순서), quest_manager.gd(get_objective_count), dsl/builtin_functions.gd, validation/narrative_validator.gd, tests/test_demo_database.gd(4) + test_localization.gd(+1), project.godot.

## 검증 방법 / 테스트 결과
- headless 전체 **130/130 PASS (exit 0, SCRIPT ERROR 0)**.
- **데모 DB 상시 검증 테스트**: 커밋된 .tres 로드 → validator **0건**(에러·경고 모두).
- 데모 콘텐츠 플로우 테스트: 첫/재방문 인사 변형, 선택지 노출 행렬(수주→진행→완료 단계별), 뇌물 비활성→보상 후 활성, 퀘스트 수주/완료/보상(130골드), ko↔en 전환 시 표시 중 대사·화자명 즉시 전환.
- **데모 씬 headless 부팅**: 메인 씬 60프레임 실행 → exit 0, 스크립트 에러 0.
- regenerate_db: 빌더 검증 클린 후 저장 OK.

## 발견된 문제 (해결됨)
- demo.tscn에서 NarrativeActor 스크립트 ext_resource 선언 누락 → 추가.
- 로컬라이징 해석 순서 결함(위) — 데모 저작 중 발견된 실사용 버그로, 전용 회귀 테스트 추가.

## 남은 한계
- 시각적 확인(실제 창 실행)은 자동화 범위 밖 — 프로젝트를 열고 ▶ 실행으로 확인 (README에 체험 순서 8단계 문서화). 원하시면 화면 캡처 검증도 도와드릴 수 있음.
- 데모는 단일 통합형 1개 (스펙의 4분할 데모는 M2 백로그).

## 다음 단계
P9: 통합 플로우 테스트(시작→분기→퀘스트→저장→재로드→재개→완료), 손상 저장 변형, 해피패스 push_error 0건 검증, run_tests.ps1 완성(테스트+CLI+에러 grep 집계).
