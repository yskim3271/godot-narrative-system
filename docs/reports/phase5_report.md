# Phase 5. 로컬라이징 (ko/en + CSV + fallback)

## 목표
ko/en 이중 언어 동작, 3단계 키 해석, CSV 왕복, 런타임 언어 전환, 누락 키 검출을 완성·검증한다.

## 구현 내용
- **CSV 도구** (`import_export/`): `csv_exporter.gd`(키 정렬, RFC-4180 이스케이프, UTF-8 무BOM) / `csv_importer.gd`(**Excel UTF-8 BOM 제거**, 헤더 검증 `key,<locale>,...`, 빈 셀은 기존 번역 비파괴, merge/replace 모드, 결과 리포트 반환).
- **픽스처**: 표준 테스트 DB에 ko/en 로컬라이징 테이블(관례 키: 대사/퀘스트 제목/캐릭터명/UI 문구) + 명시 키 대화(`loctest`) 추가.
- P2에서 선구현된 LocalizationManager(3단계 resolve)·러너 언어 변경 재표시·`text_or` UI 문구 경로를 이번 Phase에서 전부 테스트로 고정.
- **한글 폰트 결정(계획 변경)**: Noto Sans KR 번들(~10MB) 대신 **Godot 4.2+의 시스템 폰트 글리프 폴백**(Windows: 맑은 고딕) 활용 — 저장소 경량 유지. 배포용 일관 렌더링이 필요하면 테마에 폰트 지정하라고 localization.md에 안내 예정.

## 생성/수정 파일
import_export/csv_exporter.gd·csv_importer.gd(신규), tests/fixtures/db_factory.gd(loc 테이블+loctest), tests/test_localization.gd(8).

## 검증 방법 / 테스트 결과
headless 전체 **100/100 PASS (1.54s, exit 0)**. 신규 8개: 현재 언어/폴백 체인(ja→en→없음), 대화 내 3단계 해석(인라인/관례 키 ko/명시 키/누락 키 폴백), 누락 키 수집+해제+설정 비활성, **런타임 언어 전환 시 현재 대사 즉시 재표시**(ko "첫 번째", 화자명 "경비병"), 퀘스트 제목·UI 관례 키, **CSV 한글 왕복 무손실**(빈 셀 비생성 포함), BOM 제거+따옴표 콤마+불량 헤더 거부, 언어의 저장/로드 보존.

## 발견된 문제
- 없음 (첫 실행 전체 통과). 계획 대비 변경 1건: 폰트 번들 → 시스템 폴백 (위 근거).

## 다음 단계
P6 시퀀서: 명령 레지스트리+스펙 명령 13종, run-id 취소, NarrativeActor 액터 등록 노드, BarkUI.
