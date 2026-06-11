extends Node2D
## Integrated demo: dialogue + choices + conditions + quest + tracker/log +
## save/load + ko/en switching + barks + a small sequencer cutscene.
##
## Controls: arrows move · E talk · J quest log · K language · F5/F9 save/load.

const SAVE_SLOT := "demo"
const SPEED := 240.0
const TALK_DISTANCE := 96.0
const RAT_DISTANCE := 34.0

@onready var _player: Node2D = $Player
@onready var _guard: Node2D = $Guard
@onready var _quest_log: CanvasLayer = $QuestLog
@onready var _hints: Label = $Hud/Hints
@onready var _prompt: Label = $Hud/Prompt
@onready var _gold: Label = $Hud/Gold

var _rats: Array[Node2D] = []
var _bark_index := 0


func _ready() -> void:
	for child in $Rats.get_children():
		_rats.append(child)
	Narrative.language_changed.connect(func(_locale: String) -> void: _refresh_texts())
	Narrative.variable_changed.connect(func(id: String, _value: Variant) -> void:
		if id == "gold":
			_refresh_texts())
	Narrative.quest_updated.connect(func(_id: String) -> void: _sync_rats())
	Narrative.sequence_event.connect(func(event_name: String, args: Array) -> void:
		print("[demo] sequence_event: %s %s" % [event_name, args]))
	$BarkTimer.timeout.connect(_idle_bark)
	_refresh_texts()
	_sync_rats()


func _process(delta: float) -> void:
	if Narrative.is_dialogue_running():
		_prompt.visible = false
		return
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_player.position += direction * SPEED * delta
	_prompt.visible = _player.position.distance_to(_guard.position) < TALK_DISTANCE
	_check_rats()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_E:
			if not Narrative.is_dialogue_running() \
					and _player.position.distance_to(_guard.position) < TALK_DISTANCE:
				Narrative.start_dialogue("guard_talk")
		KEY_J:
			_quest_log.toggle()
		KEY_K:
			Narrative.set_language("en" if Narrative.get_language() == "ko" else "ko")
		KEY_F5:
			if Narrative.save_game(SAVE_SLOT) == OK:
				Narrative.show_alert("ui.alert.saved")
		KEY_F9:
			if Narrative.has_save(SAVE_SLOT) and Narrative.load_game(SAVE_SLOT) == OK:
				Narrative.show_alert("ui.alert.loaded")
				_sync_rats()


func _check_rats() -> void:
	if not Narrative.is_quest_active("rat_hunt"):
		return
	for rat in _rats:
		if rat.visible and _player.position.distance_to(rat.position) < RAT_DISTANCE:
			Narrative.update_objective("rat_hunt", "kill_rats")
			Narrative.show_alert("ui.alert.rat")
			return  # quest_updated -> _sync_rats hides it


## Rat visibility is derived from objective progress, so save/load and
## direct objective changes stay consistent with the world.
func _sync_rats() -> void:
	var killed := 0
	if Narrative.is_ready():
		killed = Narrative.context.quests.get_objective_count("rat_hunt", "kill_rats")
	if Narrative.is_quest_completed("rat_hunt"):
		killed = _rats.size()
	for i in _rats.size():
		_rats[i].visible = i >= killed


func _idle_bark() -> void:
	if Narrative.is_dialogue_running():
		return
	_bark_index = (_bark_index % 3) + 1
	Narrative.bark("guard", "bark.idle.%d" % _bark_index)


func _refresh_texts() -> void:
	_hints.text = Narrative.get_ui_text("ui.demo.hints", "이동: 방향키 · E: 대화 · J: 퀘스트 로그 · K: 한/영 · F5: 저장 · F9: 불러오기")
	_prompt.text = Narrative.get_ui_text("ui.demo.prompt", "[E] 대화하기")
	var gold_value: Variant = Narrative.get_variable("gold") if Narrative.has_variable("gold") else 0
	_gold.text = "%s: %s" % [Narrative.get_ui_text("ui.demo.gold", "골드"), str(gold_value)]
