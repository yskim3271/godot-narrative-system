# Phase 4. Save / Load (버전드 JSON + 마이그레이션)

## 목표
변수·퀘스트·seen/히스토리·진행 중 대화 위치·언어·게임 커스텀 데이터를 사람이 읽을 수 있는 버전드 JSON으로 저장/복원하고, 손상·버전 불일치에 견고하게 만든다.

## 구현 내용
- **NarrativeSaveManager** (`runtime/save_manager.gd`): `capture()`(순수 스냅샷) / `apply()`(검증→마이그레이션→상태 재구축→재개) / `save_game/load_game/has_save/delete_save`. 원자적 쓰기(`.tmp`→rename, 직전본 `.bak` 회전), 손상 파일 격리(`*.corrupt-<unix>`, 기존 상태 무손상), `save_version` 미래 버전 거부, 섹션별 방어적 타입 체크(깨진 섹션만 기본값), JSON float→선언 타입 복원, objective 카운트 DB 기준 재클램프, persistent=false 변수 제외, `JSON.stringify(sort_keys)` 기반 결정적 직렬화. 순수 JSON만 사용(리소스/스크립트 로드 없음 — `.tres` 인젝션 차단).
- **마이그레이션 체인** (`runtime/save_migrations.gd`): from_version→Callable 레지스트리(인스턴스 교체 가능 — 테스트/게임 확장), 단계 누락 시 로드 거부.
- **runner.try_resume()**: 저장된 위치를 **표현만 재생**(액션/시퀀서/seen 기록 재실행 없음), 선택지 조건은 복원된 변수로 재평가, `dialogue_resumed`→`line_presented`(→`choices_presented`) 방출. DB 변경으로 노드가 사라졌으면 경고+위치 폐기.
- 파사드 위임 4종 + 컨텍스트 배선.

## 생성/수정 파일
runtime/save_manager.gd·save_migrations.gd(신규), runtime/dialogue_runner.gd(try_resume), runtime/narrative_context.gd(배선), runtime/narrative.gd(위임), tests/fixtures/db_factory.gd(비영속 변수), tests/test_save_load.gd(12).

## 검증 방법 / 테스트 결과
headless 전체 **92/92 PASS (1.45s, exit 0)**. 신규 12개: 선택지 한가운데 저장→새 컨텍스트 로드→재개(시그널 순서까지)→이어서 플레이 가능, int 타입 복원, **재개 시 액션 미재실행**(gold 15 유지 — 재실행이면 20), 사라진 노드 graceful 폐기, 손상 JSON 격리+상태 무손상, 미래 버전 거부, 마이그레이션 체인(단계 누락 거부+적용 마커), 원자성(.bak=직전본/.tmp 소멸), 트랜지션 중 ERR_BUSY, 비영속 제외, 결정적 직렬화(타임스탬프 제외 바이트 동일), has/delete.

## 발견된 문제 (해결됨)
- 버전 유효성 가드를 `<= 0`으로 작성해 마이그레이션 가능한 버전 0이 invalid로 거부됨 → `< 0`(필드 부재만 invalid)으로 수정, 버전 0은 "단계 누락 거부" 경로로 일관 처리.

## 남은 한계
- 시퀀서 진행 중 상태(중간 wait 등)는 저장하지 않음 — 재개 시 시퀀스는 재생되지 않음(문서화 예정, Unity DS도 동일 정책).

## 다음 단계
P5 로컬라이징: CSV import/export(BOM), ko/en 픽스처, 런타임 언어 전환 재표시 검증, 누락 키 수집. (폰트: Godot 4.2+ 시스템 폰트 폴백이 한글을 기본 처리 — 10MB 폰트 번들 대신 문서 안내로 대체 예정)
