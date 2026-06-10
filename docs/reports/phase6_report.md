# Phase 6. 시퀀서 (명령 레지스트리 + 기본 명령) + Bark + NarrativeActor

## 목표
대사와 병행 실행되는 취소 가능한 컷신 명령 시스템(스펙 명령 13종+α), 액터 등록 노드, Bark UI를 구현한다.

## 구현 내용
- **NarrativeSequencer** (`runtime/sequencer.gd`): DSL 파서 재사용(call 전용 진입점, 인자는 내러티브 변수에 대해 평가되는 완전한 표현식), 순차 실행, **run-id 토큰 취소**(advance/select가 취소; 진행 중 wait는 조용히 만료), 미지 명령 경고+스킵, `sequence_event`/`run_finished` 시그널, `register_command()` 확장(충돌 거부).
- **내장 명령 15종** (`runtime/builtin_commands.gd`): 스펙 13종(wait, play_animation, play_audio, move_camera, focus_camera, emit_signal, call_method, show/hide_actor, set_expression, set_variable, start_quest, complete_quest) + `play_animation_wait`/`play_audio_wait`. headless 더미 오디오 드라이버 대비 **스트림 길이 타이머 폴백**, `play_audio`는 `res://` 경로만 허용(보안), 액터/플레이어/애니메이션 부재 시 경고+스킵(무크래시).
- **NarrativeActor** (`runtime/narrative_actor.gd`): NPC 자식으로 붙이는 마커 노드 — 부모를 actor_registry에 등록, 트리 이탈 시 자동 해제.
- **BarkUI** (`ui/bark_ui.gd/.tscn`): bark_requested 구독, Node2D 위 말풍선 생성, 액터당 1개(교체), 수명 후 자동 소멸.
- 파사드: `sequence_event` 재방출, `register_sequencer_command`, `play_sequence`(대화 밖 직접 실행).

## 생성/수정 파일
runtime/sequencer.gd·builtin_commands.gd·narrative_actor.gd(신규), ui/bark_ui.gd/.tscn(신규), narrative_context.gd(배선+builtin_commands 보유), narrative.gd(시그널/위임), db_factory.gd(seqtest), tests/test_sequencer.gd(12), tests/harness(무결성 게이트), tests/run_tests.gd(0-어서션 실패 처리).

## 검증 방법 / 테스트 결과
headless 전체 **112/112 PASS (3.13s, exit 0, SCRIPT ERROR 0건)**. 시퀀서 12개: wait 차단/재개+run_finished, 동기 런 즉시 완료, 미지 명령 스킵, 파스 에러 무크래시, **advance에 의한 진행 중 런 취소**(0.3s wait 후 명령 미실행 확인), 퀘스트/가시성/call_method, 애니메이션 재생+미지 애니/액터 경고, **오디오 길이 폴백으로 _wait 완료**, emit_signal 이벤트 페이로드, 인자 DSL 평가, 커스텀 명령 등록/충돌, bark 생성/교체/만료/미등록 액터.

## 발견된 문제 (중대 — 해결됨)
1. **테스트 거짓 PASS**: `builtin_commands.gd`의 타입 추론 파스 에러 2건(untyped ctx 체인에 `:=`)이 컨텍스트 컴파일을 연쇄 실패시켰는데, **GDScript 에러로 중단된 테스트 코루틴은 어서션 0개로 "통과"** 처리되고 있었음 (12/12 PASS가 전부 가짜). → (a) 파스 에러 수정(명시 타입), (b) **하니스 무결성 게이트**: 어서션 0개로 끝난 테스트는 "aborted by a script error?"로 실패 처리 + 전 어서션 카운트 추적. 이후 SCRIPT ERROR 카운트 0을 검증 루틴에 포함.
2. String vs StringName 비교 실패(`current_animation`) → 하니스 `_values_equal`이 두 타입을 텍스트 동치로 비교.

## 남은 한계
- `@time` 병렬 스케줄링·`->Message` 동기화는 M2 (현재 순차+wait).
- move/focus_camera는 2D 전용 (3D는 M2).
- 취소 시 진행 중 wait가 만료될 때까지 핸들러 참조가 유지됨(무해, 문서화).

## 다음 단계
P7: NarrativeValidator(+CLI) → 에디터 플러그인(plugin.gd, autoload 등록, 하단 패널: DB 개요+검증+CSV 버튼) → 에디터 headless 스모크.
