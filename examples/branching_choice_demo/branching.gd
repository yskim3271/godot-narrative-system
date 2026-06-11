extends Node2D
## Branching Choice Demo — 선택지/조건 분기 + 첫만남 인사 변형.
## 대화 내용은 branching.ndlg(텍스트 포맷)에서 임포트합니다: 작가는 텍스트
## 파일만 고치면 되고, 캐릭터/변수 같은 구조 데이터만 코드로 만듭니다.
## 조작: 방향키 이동 · E 대화

const SCRIPT_PATH := "res://examples/branching_choice_demo/branching.ndlg"
const ScriptParser := preload("res://addons/narrative_system/import_export/dialogue_script_parser.gd")

const SPEED := 240.0
const TALK_DISTANCE := 96.0

@onready var _player: Node2D = $Player
@onready var _npc: Node2D = $Npc
@onready var _prompt: Label = $Hud/Prompt
@onready var _stats: Label = $Hud/Stats


func _ready() -> void:
	var db := NarrativeDatabase.new()
	var merchant := NarrativeCharacter.new()
	merchant.id = "merchant"
	merchant.display_name = "상인"
	db.characters = [merchant]

	var gold := NarrativeVariable.new()
	gold.id = "gold"
	gold.type = NarrativeVariable.Type.INT
	gold.default_int = 12
	var apples := NarrativeVariable.new()
	apples.id = "apples"
	apples.type = NarrativeVariable.Type.INT
	db.variables = [gold, apples]

	var report := ScriptParser.import_file(db, SCRIPT_PATH)
	if not report.ok:
		push_error("branching demo: failed to import %s" % SCRIPT_PATH)
		return
	Narrative.load_database(db)
	Narrative.variable_changed.connect(func(_id: String, _value: Variant) -> void: _refresh_stats())
	_refresh_stats()


func _process(delta: float) -> void:
	if Narrative.is_dialogue_running():
		_prompt.visible = false
		return
	_player.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * SPEED * delta
	_prompt.visible = _player.position.distance_to(_npc.position) < TALK_DISTANCE


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_E:
		return
	if not Narrative.is_dialogue_running() \
			and _player.position.distance_to(_npc.position) < TALK_DISTANCE:
		Narrative.start_dialogue("merchant_talk")


func _refresh_stats() -> void:
	_stats.text = "골드: %s   사과: %s" % [
		str(Narrative.get_variable("gold")), str(Narrative.get_variable("apples")),
	]
