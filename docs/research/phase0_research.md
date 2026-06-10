# Phase 0 조사 보고서 — Narrative System for Godot

조사일: 2026-06-11 · 출처: Pixel Crushers 공식 매뉴얼, 각 플러그인 GitHub 저장소, Godot 공식 문서 (docs.godotengine.org/en/stable)

## 1. Unity "Dialogue System for Unity" (Pixel Crushers) 기능 분석

Unity 생태계의 사실상 표준 내러티브 툴 ($47.5~95, 리뷰 845+ 5점, Disco Elysium·Lake·Suzerain 등 출하작, 10년+ 유지보수).

| 영역 | 내용 |
|---|---|
| 데이터 구조 | 단일 **Dialogue Database** 에셋 = Actors / Conversations / Quests·Items / Locations / Variables / Templates(커스텀 필드) |
| 대화 노드 | DialogueEntry 그래프. 필드: Title, Actor, Conversant, **Menu Text**(선택지 라벨), **Dialogue Text**, **Sequence**, **Conditions**(Lua), **Script**(Lua), links(우선순위 지원). 언어 접미사(`Dialogue Text ko`)로 필드 단위 로컬라이징 |
| 스크립팅 | **Lua**: `Variable[]`/`Quest[]`/`Actor[]` 테이블 + C# 함수 등록(`Lua.RegisterFunction`). Conditions가 링크/선택지 노출을 게이팅 |
| 퀘스트 | 상태 `unassigned/active/success/failure/abandoned` + 퀘스트 엔트리(하위 목표)별 상태. Quest Log Window(3패널), Quest Tracker HUD, `OnQuestStateChange` 브로드캐스트 |
| Bark | NPC 머리 위 한 줄 대사. Bark On Idle(주기)/Trigger/Dialogue Event, `DialogueManager.Bark()` |
| Alert | `ShowAlert(text)`, `Variable["Alert"]`, 알림 큐잉 |
| Sequencer | `Command(params)@time->Message(X)` 문법. 22+ 내장 명령(Camera/Audio/AudioWait/AnimatorPlay(Wait)/MoveTo/Fade/Delay/SetVariable/SendMessage/Continue/SetPortrait...). 기본 시퀀스 `{{default}}`, C# 템플릿으로 커스텀 명령 |
| 저장 | PersistentDataManager(`GetSaveData()/ApplySaveData()` 문자열 스냅샷) + Saver 컴포넌트 + JSON + 버전 필드(`SaveSystem.version`) |
| 로컬라이징 | 필드 접미사 + Text Table 에셋 + 언어별 CSV export/import + 런타임 `SetLanguage()` |
| SimStatus | 노드별 `Untouched/WasOffered/WasDisplayed` 추적 → 처음/반복 대화 분기 |
| 마크업 | `[var=X]`, `[lua(...)]`, `[f]`, `[auto]`, `[position]`, `[panel]` 등 |
| UI | IDialogueUI 추상화 + Standard UI: 서브타이틀 패널(4종 가시성 모드), 응답 메뉴(타임아웃·자동넘버링·키보드/패드), 초상화/표정, Bubble/VN/Letterbox 프리셋 |
| 외부 연동 | articy:draft, Chat Mapper, Ink, Yarn, Twine, Arcweave 등 14종 import/export |

주요 출처: pixelcrushers.com/dialogue_system/manual2x/html/ (dialogue_editor, logic_and_lua, quests, sequencer_command_reference, save_system, localization 페이지)

## 2. Godot 생태계 현황 (2026-06, GitHub 검증)

| 플러그인 | 저작 모델 | 퀘스트 | 저장 | 로컬라이징 | Bark/Alert | 시퀀서 | 상태 |
|---|---|---|---|---|---|---|---|
| **Dialogic 2** (5.5k★, GDScript, 4.3+) | 비주얼 타임라인 | ✗ | 부분(슬롯) | CSV | ✗ | 부분(이벤트) | Alpha, 4.6+ 호환 이슈, 157 open issues |
| **Dialogue Manager v3** (3.3k★, Nathan Hoad) | 텍스트 DSL + **자체 안전 파서** | ✗ | ✗ (의도적 무상태) | gettext/POT | 예제만 | ✗ | 활발·성숙 |
| **Sprouty Dialogs** (2026-06 신규, 4.5+) | GraphEdit 그래프 | ✗ | ✗ | tres+CSV | ✗ | ✗ | 신생 |
| **Rakugo 2.2** | Ren'Py풍 텍스트 DSL | ✗ | 내장 | ✗ | ✗ | ✗ | 유지 |
| **Questify** (249★) | 퀘스트 그래프 에디터 | ✓ | ✓ | POT | ✗ | ✗ | 대화와 비연동 |
| **quest-system** (shomykohai, 455★) | 퀘스트 리소스/싱글톤 | ✓ | ✓ | CSV/POT | ✗ | ✗ | 대화와 비연동 |
| **Yarn Spinner Godot** (C# 베타 / GDScript 알파) | Yarn DSL | ✗ | 런타임 상태 | TranslationServer | ✗ | ✗ | 알파/베타 |
| **inkgd / GodotInk** | Ink 런타임 | ✗ | Ink state | Ink | ✗ | ✗ | Godot4 공식릴리즈 없음 / 2024 이후 정체 |
| **DialogueNodes / Monologue / DialogueQuest** | 그래프/외부 에디터 | ✗ | ✗ | 부분 | ✗ | ✗ | 범위 한정·일부 정체 |

## 3. 격차 분석 — Godot에 없는 것

1. **대화+퀘스트 통합 패키지 0개** — 모든 퀘스트 애드온은 대화 비연동, 모든 대화 애드온은 퀘스트 없음
2. **통합 저장 레이어 부재** — 변수+퀘스트+대화 진행 일괄 스냅샷/복원 시스템 없음
3. **대화-연출 시퀀서 통합 부재**
4. **Bark/Alert 시스템 부재**
5. **검증(밸리데이션) 도구 부재** — 끊어진 링크·누락 키·도달불가 노드 검사기 없음
6. **SimStatus류 '본 대화 추적' 부재**
7. **퀘스트 로그/트래커 기본 UI 부재**

## 4. 본 프로젝트 차별화 포인트

1. 단일 패키지(대화+조건+변수+퀘스트 UI+저장+로컬라이징+Bark/Alert+시퀀서+검증)
2. Resource 네이티브 데이터(.tres) — Inspector 편집·VCS 친화
3. eval 없는 안전한 조건/액션 DSL(자체 파서) — Godot `Expression` 클래스도 메서드 호출 허용 문제로 미사용
4. signal 우선 느슨한 결합
5. Validation 도구(에디터 패널+headless CLI)
6. 버전드 JSON 저장+마이그레이션(사람이 읽고 디버깅 가능)
7. headless 테스트 가능한 런타임

## 5. 기능 비교표

| 기능 | Unity Dialogue System | 기존 Godot 플러그인 | 본 프로젝트에서 구현할 방식 |
|---|---|---|---|
| 분기형 대화 | DialogueEntry 그래프+링크 우선순위 | Dialogic(타임라인)/DM(DSL)/Sprouty(그래프) | `DialogueNodeResource` 그래프(.tres), next_node_id+choices 링크 |
| 노드 그래프 에디터 | Conversation 노드 에디터 | Sprouty/DialogueNodes(통합형 아님) | MVP: Inspector+개요 패널 / M2: GraphEdit 에디터 |
| 텍스트 스크립트 작성 | Chat Mapper류 import | DM `.dialogue` DSL | M2: 텍스트 포맷 파서 |
| 선택지 | Menu Text+링크, `[f]/[auto]` | 각자 방식 | `ChoiceResource`(조건/액션/타깃)+ChoiceList UI(키·패드) |
| 조건/스크립트 | Lua Conditions/Script | DM 자체 파서, Dialogic 이벤트 | 자체 안전 DSL(조건식+액션문)+함수 화이트리스트 |
| 변수 시스템 | `Variable[]` (bool/str/num) | 각자 보유 | `VariableResource` 정의+`NarrativeState` 런타임+signal |
| 캐릭터/초상화/표정 | Actor+초상/표정(SetPortrait) | Dialogic 강력, DM 없음 | `CharacterResource`(expressions dict)+`set_expression` |
| 퀘스트 | 상태 5종+엔트리, Lua 연동 | 별도 애드온만 | `QuestResource`+objectives, 대화 액션 직결 |
| 퀘스트 로그 UI | Quest Log Window | 없음 | `quest_log.tscn` 기본 제공 |
| 퀘스트 트래커 HUD | Quest Tracker HUD | 없음 | `quest_tracker.tscn` 기본 제공 |
| Bark | Bark UI+Idle/Trigger/Event | 없음 | `bark_ui.tscn`+`Narrative.bark()` |
| Alert | ShowAlert+큐 | 없음 | `alert_ui.tscn`+`show_alert()` 큐 |
| Save/Load | PersistentDataManager+Savers+버전 | Rakugo만 부분적 | 버전드 JSON 스냅샷+원자적 쓰기+마이그레이션 |
| 로컬라이징 | 필드 접미사+TextTable+CSV | DM gettext/Dialogic CSV | `LocalizationTableResource`+fallback 체인+CSV+누락 검출 |
| 시퀀서/컷신 | 22+ 명령, `@time` | 없음 | 명령 레지스트리: MVP 순차+wait / M2 `@time` 병렬 |
| 외부 툴 연동 | 14종 import/export | Ink/Yarn 런타임 별개 | 로드맵(M2+): Yarn/Ink import |
| CSV import/export | DB·로컬라이징 CSV | 부분적 | 로컬라이징 CSV import/export(BOM 처리) |
| 검증 도구 | DB 체크 도구 | 없음 | `NarrativeValidator` 11종+ 검사, 에디터 패널+CLI |
| 이벤트 연동 | C# 메시지/이벤트 | signal | 전 시스템 signal+sequencer `emit_signal`/`call_method` |
| 본 노드 추적 | SimStatus 3종 | 없음 | `seen_nodes`+DSL `has_seen()` |

## 6. Godot 4 API 기술 검증 결과 (공식 문서 확인)

- **현재 안정판**: Godot 4.6.3-stable. 본 프로젝트 개발/테스트 버전 = 로컬 설치된 4.6.3. API 하한 4.4(typed Dictionary export)
- **Expression 클래스**: `base_instance` 메서드 호출 허용 등 샌드박스 불충분 → 조건식 엔진으로 **미사용**. Dialogue Manager도 자체 파서 사용(동일 결론)
- **GraphEdit**: 4.2 대개편(connection dict `from`→`from_node` 등) 후에도 변동 → 그래프 에디터는 M2
- **EditorPlugin**: autoload 등록은 `_enable_plugin()/_disable_plugin()`에서 (`_enter_tree`는 타이밍 이슈 GH-108047)
- **커스텀 리소스**: `class_name`+`@icon` 권장(add_custom_type은 레거시), typed Array/Dictionary export 가능. **`.tres`는 스크립트 임베드 가능 = 신뢰 안 되는 리소스 로드는 RCE** → 저장 파일은 순수 JSON으로
- **headless**: `godot --headless --path . -s script.gd` (SceneTree/MainLoop 상속), `quit(exit_code)`. **Windows는 `_console.exe` 빌드 필수**(일반 exe는 stdout 안 보임)
- **로컬라이징**: 애드온이 자체 Translation을 코드로 만들어 `TranslationServer.add_translation()` 가능 — 프로젝트 수준 CSV import 비의존 가능
- **첫 프레임 delta(실측)**: 엔진 부팅 시간이 첫 프레임 delta에 포함되어 `_initialize` 중 생성한 SceneTreeTimer가 조기 만료 → 테스트 러너가 시작 전 프레임 2개 펌프 + 테스트별 프레임 경계 정렬로 해결
