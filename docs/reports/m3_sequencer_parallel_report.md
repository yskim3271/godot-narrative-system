# M3-1. 시퀀서 @time 병렬 + 메시지 동기화 + 3D 지원

## 목표
Unity Dialogue System 패리티의 시퀀서 고도화: ① `@time` 병렬 스케줄링, ② `->message` / `@message` 동기화, ③ Camera3D 명령(`move_camera_3d`, 3D `focus_camera`)과 3D bark. 기존 순차 실행 스크립트는 그대로 동작해야 한다(상위 호환).

## 구현 내용
- **DSL 확장 (lexer/parser)**: `@`(punct)·`->`(op) 토큰 추가. `parse_sequence` 한정 줄 장식 — `cmd() @ 2.5`(timed), `cmd() @ message("name")`(on_message), `cmd() -> "name"`/`-> message("name")`(notify, 스케줄과 결합 가능). AST는 기존 배열 컨벤션의 래퍼: `["timed", s, inner]`/`["on_message", n, inner]`/`["notify", n, inner]`(스케줄이 최외곽). 장식 없는 줄은 기존 `["call", ...]` 그대로(소비자 호환). 조건/액션 모드에서 두 토큰은 위치 있는 파스 에러.
- **`sequencer.gd` 병렬 실행 모델**: 장식 없는 줄 = 기존 그대로의 **순차 스레드**, `@` 줄 = 런 시작 시 분리되어 병렬(타이머/메시지 대기). 잡 카운터(순차 스레드 1 + 스케줄 줄 N)로 `run_finished`는 **전부 끝나야** 발생. `send_message(name)`(public, 파사드 `send_sequencer_message`)가 `@message` 대기 줄을 풀고 `sequencer_message` 시그널 방출. `->`는 줄 완료 시 브로드캐스트 — **명령이 스킵돼도 발생**(오타 데드락 방지). 취소는 기존 run-id 토큰 + 내부 `_release_message("")` 플러시로 메시지 대기 코루틴을 즉시 깨워 종료(시그널 대기 누수 없음). `setup(evaluator, tree)`로 SceneTree 주입(@time 타이머용, 트리 없으면 경고 후 즉시 실행).
- **3D 카메라**: `move_camera_3d(x,y,z[,duration])` 신규(활성 Camera3D 트윈). `focus_camera`는 액터 공간으로 디스패치 — Node2D는 기존(카메라 이동), **Node3D는 제자리 회전으로 액터 주시**(`looking_at`, up 벡터 평행 시 FORWARD 폴백, duration 0 = 즉시).
- **3D bark (`bark_ui.gd`)**: Node3D 액터의 말풍선은 BarkUI 자신의 화면 공간 자식으로 생성, `_process`에서 활성 Camera3D로 `bubble_offset_3d`(기본 (0,2.2,0)) 위치를 투영해 추적(카메라 뒤면 숨김). 교체/만료 정책은 2D와 동일(버블 빌드·만료 로직 공통화). 3D 버블 없으면 `set_process(false)`.
- **검증기**: BUILTIN_COMMANDS에 `move_camera_3d`, 시퀀스 문장 장식 언랩 후 명령 검사.

## 발견된 문제 (해결됨)
1. **`@`를 불법 문자로 단정한 렉서 테스트**: `@` 합법화로 `test_illegal_character_reports_position`이 깨짐 → `$`로 교체 + 장식 토큰화 테스트 추가. (의도된 동작 변화가 테스트로 정확히 표면화된 사례.)
2. 무타입 변수에 `:=` 추론 불가 파스 에러(테스트 코드) → 명시 타입.

## 생성/수정 파일
runtime/dsl/lexer.gd·parser.gd, runtime/sequencer.gd(병렬 실행 모델)·narrative_context.gd(tree 주입)·narrative.gd(send_sequencer_message·sequencer_message)·builtin_commands.gd(3D 카메라), ui/bark_ui.gd(3D), validation/narrative_validator.gd, tests/test_lexer.gd(+1, 1 수정)·test_parser.gd(+3)·test_sequencer.gd(+9), docs/sequencer.md·dsl.md·api_reference.md·known_limitations.md·roadmap.md.

## 검증 방법 / 테스트 결과
- 전체 파이프라인 **ALL GREEN**: 유닛 **212/212 (6.7s, SCRIPT ERROR 0)** · 해피패스 순수성 클린 · 데모 DB strict 0/0 · 데모 5종 부팅 OK. 기존 시퀀서 테스트 12종 무수정 통과(상위 호환 확인).
- parser 3종: 장식 4형태 AST·미장식 호환, 에러 6형태(잘못된 @·음수·빈 이름·비문자열·액션 모드 거부), 조건 모드 토큰 거부.
- sequencer 9종: @time 병렬(순차 즉시+지연 발화+run_finished 1회), @0 시작 동기 실행, `->`가 @message 대기를 동기 해제(+sequencer_message), 게임 코드 send_message 해제(타 메시지 무반응), 취소 시 타이머·메시지 대기 모두 사멸, 스킵 명령도 notify(데드락 방지), 장식 파스 에러 무크래시, 3D 카메라(즉시 이동+제자리 조준 dot>0.99), 3D bark(화면 공간 생성·투영 추적·만료).
- 에디터 GUI 변경 없음 → 수동 확인 대상 아님(함정 ⑧⑨ 범주 밖).

## 남은 한계 (known_limitations.md 갱신)
- `@time`은 숫자 리터럴만(표현식 불가, Unity DS 동일). 카메라 명령은 활성 카메라 1대 대상.
- 3D bark는 화면 공간 투영(깊이 가림 없음).

## 다음 단계
M4 — Godot Asset Library 배포 패키징 (같은 세션 C 작업).
