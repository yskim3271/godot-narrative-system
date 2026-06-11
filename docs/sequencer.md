# 시퀀서 (컷신 명령)

대화 노드의 `sequencer_commands`에 적는 연출 명령입니다. **대사 표시와 병행**으로 순차 실행되며, 플레이어가 `advance()`/`select_choice()` 하면 진행 중인 런이 취소됩니다(연출이 입력을 막지 않음).

```
set_expression("guard", "happy")
play_animation("guard", "wave")
wait(0.5)
focus_camera("guard", 0.4)
emit_signal("quest_given")
```

- 한 줄에 명령 하나(또는 `;` 구분), 인자는 **완전한 DSL 표현식** — 변수를 쓸 수 있습니다: `set_variable("gold", gold + 10)`
- 미지 명령/없는 액터는 **경고 후 스킵** (연출이 게임을 죽이지 않음)
- 대화 밖에서도 실행 가능: `Narrative.play_sequence("wait(1)\nemit_signal(\"boom\")")`

## 액터 등록

명령의 대상은 **액터 레지스트리**의 노드입니다. NPC 씬에 `NarrativeActor` 노드를 자식으로 추가하면 부모가 `actor_id`(기본: 부모 이름)로 등록됩니다. 코드 등록: `Narrative.register_actor("guard", node)`.

## 내장 명령

| 명령 | 동작 |
|---|---|
| `wait(seconds)` | 지정 시간 대기 |
| `play_animation(actor, anim)` | 액터(또는 하위)의 AnimationPlayer 재생 |
| `play_animation_wait(actor, anim)` | 재생 후 끝날 때까지 대기 (루프 애니메이션엔 쓰지 말 것) |
| `play_audio(actor [, "res://...stream"])` | 액터의 AudioStreamPlayer 재생 (경로는 res:// 만 허용) |
| `play_audio_wait(actor [, path])` | 재생 후 스트림 길이만큼 대기 (headless에서도 안전) |
| `move_camera(x, y [, duration=0.5])` | 활성 Camera2D 이동 (트윈) |
| `focus_camera(actor [, duration=0.5])` | 액터 위치로 카메라 이동 |
| `emit_signal(name, args...)` | `Narrative.sequence_event(name, args)` 방출 — 게임 코드 연동 지점 |
| `call_method(actor, method, args...)` | 등록된 액터 노드의 메서드 호출 |
| `show_actor(actor)` / `hide_actor(actor)` | visible 토글 |
| `set_expression(char_id, expr)` | 초상화 표정 변경 (`""` = 기본) |
| `set_variable(name, value)` | 내러티브 변수 대입 |
| `start_quest(id)` / `complete_quest(id)` | 퀘스트 제어 |

## 게임 코드와의 연동

```gdscript
# 방법 1 — 시그널 (권장: 느슨한 결합)
Narrative.sequence_event.connect(func(name, args):
	if name == "quest_given":
		$Fireworks.restart())

# 방법 2 — 커스텀 명령 등록
Narrative.register_sequencer_command("shake_screen", func(args: Array) -> void:
	var strength := float(args[0]) if args.size() > 0 else 8.0
	await my_camera.shake(strength))   # await 가능 — 끝날 때까지 시퀀스가 대기
```

## 동작 세부

- 취소는 "다음 명령부터 중단"입니다 — 이미 `wait()` 중이던 코루틴은 타이머가 만료될 때 조용히 끝납니다(부수효과 없음).
- 저장/로드 시 **시퀀스 진행 상태는 저장되지 않습니다** — 재개 시 연출은 재생되지 않습니다(액션과 동일한 "효과는 이미 반영됨" 원칙).
- `@time` 병렬 스케줄링(Unity DS 스타일)은 로드맵 항목입니다 — 현재는 순차 + `wait()` 조합.
