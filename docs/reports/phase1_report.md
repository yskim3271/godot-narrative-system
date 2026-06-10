# Phase 1. 스캐폴드 + 테스트 하니스 + 설계 문서

## 목표
Godot 4.6.3 프로젝트 골격, 애드온 뼈대, 모든 후속 Phase의 검증 기반이 될 자체 headless 테스트 하니스, 핵심 설계 문서를 구축한다.

## 구현 내용
- git 저장소 초기화 (main 브랜치)
- Godot 프로젝트 생성 (`project.godot`, GL Compatibility 렌더러, `icon.svg`)
- 애드온 뼈대: `plugin.cfg`, `plugin.gd`(P7에서 확장될 스텁), `version.gd`(VERSION/SAVE_VERSION 상수)
- 자체 테스트 하니스 (외부 프레임워크 비의존):
  - `tests/run_tests.gd` — SceneTree 스크립트. `tests/test_*.gd` 자동 발견, 테스트 메서드별 새 인스턴스(완전 격리), sync/async 균일 await, `--filter=` 지원, exit code 0/1
  - `tests/harness/test_case.gd` — 어서션 누적형 베이스 클래스 (assert_eq/true/false/null/contains/almost_eq + wait_seconds/wait_frame)
  - `tests/harness/signal_recorder.gd` — 시그널 방출 순서/인자 기록 (0~4 인자)
  - `tests/test_smoke.gd` — 하니스 자체 검증 5종
- `scripts/run_tests.ps1` — import → 테스트 일괄 실행 래퍼
- 설계 문서: `docs/architecture.md`, `docs/dsl.md`, `docs/save_format.md`, `docs/signals.md`
- Phase 0 조사 보고서 저장: `docs/research/phase0_research.md`

## 생성/수정 파일
| 파일 | 역할 |
|---|---|
| project.godot / icon.svg / .gitignore | Godot 프로젝트 루트 |
| addons/narrative_system/plugin.cfg, plugin.gd, version.gd | 애드온 뼈대 |
| addons/narrative_system/tests/run_tests.gd | headless 테스트 러너 |
| addons/narrative_system/tests/harness/test_case.gd, signal_recorder.gd | 테스트 베이스/도구 |
| addons/narrative_system/tests/test_smoke.gd | 하니스 스모크 테스트 |
| scripts/run_tests.ps1 | 검증 일괄 실행 스크립트 |
| docs/architecture.md, dsl.md, save_format.md, signals.md | 설계 문서 |
| docs/research/phase0_research.md | Phase 0 조사 보고서 |

## 동작 방식
`Godot_v4.6.3_win64_console.exe --headless --path . -s res://addons/narrative_system/tests/run_tests.gd` 실행 → 러너가 프레임 2개를 펌프(부팅 delta 제거) → `tests/test_*.gd`를 정렬 순서로 로드 → 각 `test_*` 메서드를 프레임 경계에서 새 인스턴스로 실행(await) → 실패 누적 출력 → `quit(0|1)`.

## 검증 방법
1. `--import` 클린 실행
2. 스모크 5종 실행 (어서션, 인스턴스 격리 2종, 비동기 타이머, 시그널 레코더)
3. 고의 실패 테스트 파일 추가 → exit 1 확인 → 제거

## 테스트 결과
- import: exit 0
- 스모크: **5/5 PASS, exit 0**
- 고의 실패 검증: exit 1 + 실패 메시지 정상 출력 후 임시 파일 제거 확인

## 발견된 문제 (해결됨)
1. **첫 프레임 delta 부풀림(실측)**: 엔진 부팅 시간 전체가 첫 프레임 delta에 포함되어 `_initialize` 중 생성된 SceneTreeTimer가 즉시~조기 만료 (50ms 타이머가 1ms에 리턴). → 러너 시작 시 2프레임 펌프로 해결.
2. **동기 작업의 delta 선입금**: 프레임 사이에 수행된 동기 작업(스크립트 로드 등) 시간이 다음 프레임 delta에 합산되어 타이머에 선입금됨 (50ms 타이머가 21ms에 리턴). → 각 테스트를 프레임 경계에서 시작하도록 러너 수정 + 타이밍 어서션은 프레임 양자화(최대 1프레임 조기)를 감안한 하한 사용. 이 지식은 P6 시퀀서 테스트 작성에 그대로 적용된다.

## 다음 단계
P2 런타임 코어: 리소스 10종 → DSL(렉서/파서/평가기) → NarrativeState/Context → DialogueRunner → DialogueBox/ChoiceList UI. DSL 테스트 28종을 먼저 작성해 파서를 검증한 뒤 러너를 올린다.
