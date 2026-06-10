# Phase 7. 에디터 플러그인 + Validator

## 목표
에디터 통합(autoload 등록, 하단 패널: DB 개요/검증/CSV 도구)과, 에디터 비의존 정적 분석기(NarrativeValidator)+headless CLI를 구현한다.

## 구현 내용
- **NarrativeValidator** (`validation/narrative_validator.gd`, 에디터 비의존): 검사 항목 — 시작 노드 누락/부재, 끊어진 next/choice 타깃, 도달불가 노드(BFS), 미지 speaker/character, **DSL AST 정적 분석**(조건/액션/시퀀스 파스 실패+위치, 미지 함수(설정의 declared_external_functions로 완화 가능), 미지 시퀀서 명령, `start_quest`/`has_seen`/`set_expression` 등 **리터럴 인자 id 실존 검증**(quest/objective/dialogue/node/character), 미선언 변수 읽기/대입), 카테고리 전역 중복 id+빈 id, **공유 리소스 인스턴스 검출**(Inspector 배열 복제 함정), id 문자셋, 누락 로컬라이징 키, 선행조건 실존, target_count 유효성, **조건-스킵 사이클**(의도치 않은 무한 루프 후보). 심각도 2단계(error/warning).
- **validate_cli** (`validation/validate_cli.gd`): `--db=<path> [--strict]`, exit 0/1/2.
- **에디터 플러그인** (`plugin.gd` 완성): `_enable_plugin()`→autoload 등록+`narrative_system/database_path` 설정 등록(FILE 힌트), `_disable_plugin()`→해제(가드 포함), `_enter_tree()`→하단 패널. 패널은 autoload 비의존(설정에서 DB 직접 로드).
- **하단 패널 3종** (`editor/`, 코드 빌드): narrative_panel(툴바: 경로/Browse/Load/Validate/CSV Export·Import+상태), database_editor(카테고리 트리, 더블클릭→Inspector 열기), validation_panel(심각도 색상 이슈 목록).
- **UI 재바인딩 지원**: autoload 자동 바인딩 후 setup() 재호출 시 이전 연결 해제 후 교체(6개 UI), 파사드 `is_ready()`로 미설정 autoload에 대한 초기 풀 가드.

## 생성/수정 파일
validation/ 2개(신규), plugin.gd(완성), editor/ 3개(신규), ui/ 6개(재바인딩), runtime/narrative.gd(is_ready), tests/fixtures(clean() 추가), tests/test_validator.gd(13), project.godot(editor_plugins enabled).

## 검증 방법 / 테스트 결과
1. headless 전체 **125/125 PASS (exit 0, SCRIPT ERROR 0)** — validator 13종 포함(클린 DB 0건 보장, 표준 픽스처의 의도적 결함(broken/cycle/missing key) 검출 확인).
2. **에디터 headless 스모크**: `--headless --editor --quit` → exit 0, SCRIPT ERROR 0 (플러그인+패널 로드 정상).
3. **CLI 종단**: 임시 .tres 생성 → clean: `0 error/0 warning, exit 0` / broken: `1 error(+파생 경고 2), exit 1` / 부재: `exit 2`.

## 발견된 문제
- autoload가 등록되면 UI들이 컨텍스트 없는 파사드에 선바인딩되어 테스트/늦은 설정 시나리오가 깨지는 문제 → 재바인딩+`is_ready()` 가드로 해결 (P8에서 autoload 추가 전에 선제 처리).
- 한계: `_enable_plugin()` 경로(체크박스 토글)는 headless로 자동화 불가 — 에디터 UI 수동 토글로만 검증 가능(문서화). 저장소에는 P8에서 autoload 항목을 직접 커밋.

## 다음 단계
P8 통합 데모. 시작 전 로컬라이징 해석 순서 1건 교정 예정: "인라인=기본 언어 텍스트" 원칙에 맞게 fallback 언어 테이블보다 인라인을 우선(현재 구조는 ko 기본+en 번역 시 ko 사용자에게 en이 노출될 수 있음) — 테스트와 함께 수정.
