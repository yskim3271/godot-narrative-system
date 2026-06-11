# 확장 가이드

## 1. 게임 함수를 조건/액션에 노출

대화 데이터가 게임 상태를 읽고 쓰는 유일한 통로는 **화이트리스트 함수**입니다:

```gdscript
# 게임 초기화 시 (예: 인벤토리 autoload의 _ready)
Narrative.register_function("has_item", func(item_id: String) -> bool:
	return Inventory.count(item_id) > 0)
Narrative.register_function("give_item", func(item_id: String) -> bool:
	return Inventory.add(item_id))
```
대화 데이터에서: `condition = has_item("cellar_key")`, `actions = give_item("reward_sword")`.

규칙:
- 반환값은 `null | bool | int | float | String`만 (그 외 타입은 에러 처리)
- 내장/기존 이름과 충돌 시 등록 거부 (`override = true`로 명시 교체)
- **검증기에게 알려주기**: 에디터 Validate가 게임 등록 함수를 알 수 없으므로, `NarrativeSettings.declared_external_functions`에 이름을 적으면 "unknown function" 에러가 사라집니다

## 2. 커스텀 시퀀서 명령

```gdscript
Narrative.register_sequencer_command("fade_out", func(args: Array) -> void:
	var duration := float(args[0]) if args.size() > 0 else 0.5
	await ScreenFader.fade_out(duration))   # await하면 다음 명령이 기다림
```
취소 의미론: 명령 사이에서만 중단됩니다 — 긴 await를 갖는 명령은 내부에서 스스로 중단 조건을 두는 것을 권장.

## 3. 커스텀 UI 만들기

기본 UI 7종은 전부 **레퍼런스 구현**입니다. 같은 시그널을 구독하면 어떤 UI로도 교체 가능합니다:

```gdscript
extends Control  # 나만의 대화창

func _ready() -> void:
	Narrative.line_presented.connect(_on_line)
	Narrative.choices_presented.connect(_on_choices)
	Narrative.dialogue_ended.connect(func(_id): hide())

func _on_line(speaker_id: String, text: String) -> void:
	show()
	$Name.text = Narrative.get_character_display_name(speaker_id)
	$Text.text = text
	# 진행은 Narrative.advance(), 선택은 Narrative.select_choice(id)
```
시그널 계약 전체: [signals.md](signals.md). 늦게 생성되는 UI는 `Narrative.get_current_node()` / `get_available_choices()` / `get_current_line_text()`로 현재 상태를 1회 풀(pull)하세요.

## 4. autoload 없이 쓰기 (서브씬·테스트·멀티 컨텍스트)

런타임은 autoload에 의존하지 않습니다:

```gdscript
var ctx := NarrativeContext.create(load("res://my_db.tres"), get_tree())
ctx.runner.start_dialogue("hello")
ctx.runner.line_presented.connect(...)
# 기본 UI도 연결 가능: dialogue_box.setup(ctx.runner)
```
테스트 작성 시 이 패턴을 그대로 쓰면 됩니다 — `addons/narrative_system/tests/`의 137개 테스트가 전부 이 방식입니다.

## 5. 저장 파일에 게임 데이터 싣기 / 마이그레이션 확장

- `Narrative.context.state.custom_data` (JSON-safe) → 같은 슬롯에 저장/복원
- 스키마 확장 시: `context.save_manager.migrations[버전] = Callable` 주입 가능 ([save_load.md](save_load.md))

## 6. 알아두면 좋은 내부 규칙

- 서브시스템은 전부 RefCounted — Node는 autoload 파사드뿐
- **RefCounted 대상 메서드 Callable은 약참조**입니다(4.6.3 실측): 등록하는 콜러블의 소유 객체는 직접 살려두세요 (람다는 캡처를 강참조하므로 안전)
- 시그널 핸들러에서 `advance()`/`select_choice()` 호출은 안전(내부 큐), `start_dialogue()`는 트랜지션 중 거부 — 대화 연쇄는 `dialogue_ended`에서 시작하세요
