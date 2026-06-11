# Narrative System for Godot

**Godot 4.x용 올인원 내러티브 시스템 애드온** — 분기 대화, 선택지, 조건/변수, 퀘스트(로그·트래커 UI 포함), 저장/불러오기, 로컬라이징(ko/en), Bark/Alert, 컷신 시퀀서, 검증 도구를 하나의 패키지로 제공합니다. Unity의 "Dialogue System for Unity"가 차지하는 포지션을 Godot에서 목표로 합니다.

- **요구 버전**: Godot 4.4+ (4.6.3에서 개발·테스트)
- **언어**: GDScript (외부 의존성 없음)
- **라이선스**: MIT

## 왜 이 애드온인가

| | Dialogic 2 | Dialogue Manager | 퀘스트 애드온들 | **Narrative System** |
|---|---|---|---|---|
| 분기 대화 + 조건/변수 | ✓ | ✓ | ✗ | ✓ |
| 퀘스트 + 로그/트래커 UI | ✗ | ✗ | ✓ (대화 비연동) | ✓ (**대화 액션 직결**) |
| 통합 저장/불러오기 | 부분 | ✗ (무상태 설계) | 부분 | ✓ (버전드 JSON + 마이그레이션) |
| Bark / Alert | ✗ | ✗ | ✗ | ✓ |
| 컷신 시퀀서 | 부분 | ✗ | ✗ | ✓ (확장 가능 명령) |
| 데이터 검증 도구 | ✗ | ✗ | ✗ | ✓ (에디터 패널 + CLI) |

## 핵심 특징

- **Resource 네이티브**: 모든 데이터가 `.tres` — Inspector에서 편집, VCS 친화적
- **eval 없는 안전한 DSL**: 조건/액션/시퀀서 명령은 자체 파서로 해석 (임의 코드 실행 불가, 게임 함수는 화이트리스트 등록)
- **signal 우선 느슨한 결합**: 게임 코드는 `Narrative` 파사드의 시그널만 구독 — 모든 기본 UI는 교체 가능한 레퍼런스 구현
- **headless 테스트 가능**: UI 없이 전체 로직 실행 — 자체 테스트 137개 + 해피패스 무에러 게이트 + 데이터 검증 CLI
- **본 노드 추적(SimStatus)**: `has_seen()`으로 첫만남/재방문 분기
- **사람이 읽는 저장 파일**: 순수 JSON, 원자적 쓰기, 손상 격리, 스키마 마이그레이션

## 빠른 시작

```gdscript
# 1) addons/narrative_system 폴더를 프로젝트에 복사하고 플러그인을 활성화
#    (프로젝트 설정 → 플러그인 → Narrative System 체크 → autoload 자동 등록)
# 2) 프로젝트 설정 narrative_system/database_path 에 데이터베이스 .tres 지정
# 3) 씬에 ui/dialogue_box.tscn, ui/choice_list.tscn 인스턴스 추가
# 4) 대화 시작:
Narrative.start_dialogue("guard_talk")

# 시그널 구독:
Narrative.dialogue_ended.connect(func(id): player.can_move = true)
Narrative.quest_updated.connect(func(id): print("quest: ", id))
```

자세한 설치·첫 대화 만들기: **[docs/getting_started.md](docs/getting_started.md)**

## 데모

프로젝트를 Godot로 열고 ▶ 실행 — [examples/integrated_demo](examples/integrated_demo/README.md)가 모든 기능(분기 대화, 조건부 선택지, 퀘스트+트래커, 저장/불러오기, 한/영 전환, bark, 컷신)을 한 씬에서 시연합니다.

## 문서

| 문서 | 내용 |
|---|---|
| [getting_started.md](docs/getting_started.md) | 설치(플러그인/수동 autoload), 10분 만에 첫 대화 |
| [dialogue_authoring.md](docs/dialogue_authoring.md) | Inspector 저작 워크플로, 분기 패턴, 함정 |
| [dsl.md](docs/dsl.md) | 조건/액션 미니 언어 문법·의미론 |
| [quest_system.md](docs/quest_system.md) | 퀘스트 상태·objective·보상·UI |
| [save_load.md](docs/save_load.md) · [save_format.md](docs/save_format.md) | 사용법 · JSON 스키마/마이그레이션 |
| [localization.md](docs/localization.md) | 키 규칙, CSV 왕복, 언어 전환, 폰트 |
| [sequencer.md](docs/sequencer.md) | 내장 명령 레퍼런스, 커스텀 명령 |
| [extending.md](docs/extending.md) | 게임 함수/명령 등록, 커스텀 UI |
| [api_reference.md](docs/api_reference.md) | 파사드 API·시그널 전체 |
| [architecture.md](docs/architecture.md) · [signals.md](docs/signals.md) | 내부 설계 |
| [security_notes.md](docs/security_notes.md) | .tres 신뢰 경계, 저장 파일 안전성 |
| [known_limitations.md](docs/known_limitations.md) · [roadmap.md](docs/roadmap.md) | 한계와 다음 단계 |
| [test_report.md](docs/test_report.md) | 테스트 현황과 실행 방법 |

## 테스트 실행

```powershell
.\scripts\run_tests.ps1          # import → 유닛 137개 → 해피패스 순수성 → DB 검증
.\scripts\run_tests.ps1 -Filter lexer
```

## 저장소 구조

```
addons/narrative_system/   # 애드온 본체 (이 폴더만 복사하면 설치 끝)
  runtime/                 #   파사드·러너·퀘스트·저장·로컬라이징·시퀀서 (+dsl/)
  resources/               #   데이터 모델 (NarrativeDatabase 등 10종)
  ui/                      #   레퍼런스 UI 7종 (.tscn/.gd)
  editor/                  #   에디터 하단 패널 (@tool)
  validation/              #   정적 검증기 + CLI (에디터 비의존)
  import_export/           #   로컬라이징 CSV
  tests/                   #   자체 headless 테스트 하니스 + 137 테스트
examples/integrated_demo/  # 통합 데모 (▶ 실행)
docs/                      # 문서 · 설계 · Phase별 구현 보고서
```
