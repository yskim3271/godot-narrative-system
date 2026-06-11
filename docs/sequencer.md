# 시퀀서 (컷신 명령)

대화 노드의 `sequencer_commands`에 적는 연출 명령입니다. **대사 표시와 병행**으로 실행되며, 플레이어가 `advance()`/`select_choice()` 하면 진행 중인 런 전체가 취소됩니다(연출이 입력을 막지 않음).

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

## 병렬 스케줄링과 메시지 동기화 (`@` / `->`)

장식 없는 줄은 위에서 아래로 **순차** 실행됩니다(기존 동작 그대로). 줄 끝에 장식을 붙이면 그 줄이 순차 흐름에서 분리되어 **병렬** 스케줄됩니다 — Unity Dialogue System의 `@time`/`->Message` 패리티:

```
play_animation("guard", "bow")                 # t=0 순차 실행
play_audio("guard", "res://sfx/horn.ogg") @ 0.5   # 런 시작 0.5초 후, 병렬
show_actor("king") @ message("horn_done")      # 메시지를 기다렸다가 실행
wait(1.2) -> "horn_done"                       # 이 줄이 끝나면 메시지 브로드캐스트
```

| 장식 | 의미 |
|---|---|
| `cmd(...) @ 2.5` | **런 시작 기준** 2.5초 뒤에 실행 (숫자 리터럴 초, `@ 0` = 시작 즉시) |
| `cmd(...) @ message("name")` | `"name"` 메시지가 브로드캐스트되면 실행 |
| `cmd(...) -> "name"` (또는 `-> message("name")`) | 이 줄이 **끝나면** `"name"` 브로드캐스트 — `@` 와 결합 가능: `cmd() @ 1 -> "done"` |

- 메시지 출처: `->` 장식, 또는 게임 코드의 `Narrative.send_sequencer_message("name")` (게임플레이 이벤트로 연출을 게이트).
- 모든 브로드캐스트는 `Narrative.sequencer_message(message)` 시그널로도 들립니다.
- `run_finished`는 순차 흐름 **그리고** 모든 스케줄 줄이 끝나야 발생합니다.
- 취소(advance 등)는 런 전체에 적용 — 대기 중인 `@time` 타이머/메시지 대기 줄도 조용히 죽습니다.
- `->` 메시지는 명령이 경고로 스킵돼도 발생합니다(오타가 대기 줄을 영원히 잠그지 않도록).
- 같은 메시지를 여러 줄이 기다리면 전부 풀립니다. 메시지는 런 내부 상태를 갖지 않습니다(먼저 브로드캐스트되고 나중에 대기를 시작하면 다음 브로드캐스트까지 대기).

## 액터 등록

명령의 대상은 **액터 레지스트리**의 노드입니다. NPC 씬에 `NarrativeActor` 노드를 자식으로 추가하면 부모가 `actor_id`(기본: 부모 이름)로 등록됩니다. 코드 등록: `Narrative.register_actor("guard", node)`. 2D/3D 노드 모두 등록 가능합니다.

## 내장 명령

| 명령 | 동작 |
|---|---|
| `wait(seconds)` | 지정 시간 대기 |
| `play_animation(actor, anim)` | 액터(또는 하위)의 AnimationPlayer 재생 |
| `play_animation_wait(actor, anim)` | 재생 후 끝날 때까지 대기 (루프 애니메이션엔 쓰지 말 것) |
| `play_audio(actor [, "res://...stream"])` | 액터의 AudioStreamPlayer 재생 (경로는 res:// 만 허용) |
| `play_audio_wait(actor [, path])` | 재생 후 스트림 길이만큼 대기 (headless에서도 안전) |
| `move_camera(x, y [, duration=0.5])` | 활성 Camera2D 이동 (트윈) |
| `move_camera_3d(x, y, z [, duration=0.5])` | 활성 **Camera3D** 이동 (트윈) |
| `focus_camera(actor [, duration=0.5])` | 2D 액터: 카메라가 액터 위치로 이동. **3D 액터: Camera3D가 제자리에서 액터를 바라보도록 회전** |
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
	await my_camera.shake(strength))   # await 가능 — 끝날 때까지 그 줄이 대기

# 방법 3 — 메시지로 연출을 게임 이벤트에 동기화
# 시퀀스:  open_door("gate") \n play_animation("king", "enter") @ message("gate_open")
Narrative.register_sequencer_command("open_door", func(args: Array) -> void:
	await $Gate.open())
# 또는 게임 코드 임의 시점: Narrative.send_sequencer_message("gate_open")
```

## 동작 세부

- 취소는 "다음 명령부터 중단"입니다 — 이미 `wait()` 중이던 코루틴은 타이머가 만료될 때 조용히 끝납니다(부수효과 없음). 메시지 대기 줄은 취소 시 즉시 풀려 조용히 끝납니다.
- 저장/로드 시 **시퀀스 진행 상태는 저장되지 않습니다** — 재개 시 연출은 재생되지 않습니다(액션과 동일한 "효과는 이미 반영됨" 원칙).
- `@time`은 SceneTree 타이머를 씁니다 — 트리 없는 컨텍스트(특수한 headless 코드)에선 경고 후 즉시 실행됩니다.
