extends Node2D
## Localization + Cutscene Demo — 런타임 한/영 전환과 시퀀서 컷신, bark.
## 조작: 방향키 이동 · E 대화 · K 한/영 전환 (대화 중에도 즉시 반영)

const SPEED := 240.0
const TALK_DISTANCE := 96.0

@onready var _player: Node2D = $Player
@onready var _npc: Node2D = $Npc
@onready var _prompt: Label = $Hud/Prompt
@onready var _hints: Label = $Hud/Hints

var _bark_index := 0


func _ready() -> void:
	# The NarrativeActor child already registered "bard" with the autoload;
	# load_database() carries the actor registry over to the new context.
	Narrative.load_database(_build_database())
	Narrative.language_changed.connect(func(_locale: String) -> void: _refresh_texts())
	Narrative.sequence_event.connect(func(event_name: String, args: Array) -> void:
		print("[loc_cutscene] sequence_event: %s %s" % [event_name, args]))
	$BarkTimer.timeout.connect(_idle_bark)
	_refresh_texts()


func _process(delta: float) -> void:
	if Narrative.is_dialogue_running():
		_prompt.visible = false
		return
	_player.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * SPEED * delta
	_prompt.visible = _player.position.distance_to(_npc.position) < TALK_DISTANCE


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_E:
			if not Narrative.is_dialogue_running() \
					and _player.position.distance_to(_npc.position) < TALK_DISTANCE:
				Narrative.start_dialogue("bard_show")
		KEY_K:
			Narrative.set_language("en" if Narrative.get_language() == "ko" else "ko")


func _idle_bark() -> void:
	if Narrative.is_dialogue_running():
		return
	_bark_index = (_bark_index % 2) + 1
	Narrative.bark("bard", "bark.tune.%d" % _bark_index)


func _refresh_texts() -> void:
	_hints.text = Narrative.get_ui_text("ui.demo.hints", "이동: 방향키 · E: 대화 · K: 한/영")
	_prompt.text = Narrative.get_ui_text("ui.demo.prompt", "[E] 대화하기")


func _build_database() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.settings = NarrativeSettings.new()
	db.settings.default_language = "ko"
	db.settings.fallback_language = "en"

	var bard := NarrativeCharacter.new()
	bard.id = "bard"
	bard.display_name = "음유시인"
	db.characters = [bard]

	var intro := NarrativeDialogueNode.new()
	intro.id = "intro"
	intro.speaker_id = "bard"
	intro.text = "노래 한 곡 들어보겠나? 자, 시작하지!"
	intro.next_node_id = "show"
	var show_node := NarrativeDialogueNode.new()
	show_node.id = "show"
	show_node.speaker_id = "bard"
	show_node.text = "(현란한 연주가 이어진다)"
	show_node.sequencer_commands = "play_animation(\"bard\", \"perform\")\nwait(0.4)\nfocus_camera(\"bard\", 0.4)\nemit_signal(\"flourish\")\nwait(0.6)\nmove_camera(0, 0, 0.4)"
	show_node.next_node_id = "outro"
	var outro := NarrativeDialogueNode.new()
	outro.id = "outro"
	outro.speaker_id = "bard"
	outro.text = "어떤가, 마음에 들었는가?"

	var dialogue := NarrativeDialogue.new()
	dialogue.id = "bard_show"
	dialogue.start_node_id = "intro"
	dialogue.nodes = [intro, show_node, outro]
	db.dialogues = [dialogue]

	var table := NarrativeLocalizationTable.new()
	table.set_text("dlg.bard_show.intro.text", "en", "Care for a song? Here we go!")
	table.set_text("dlg.bard_show.show.text", "en", "(A dazzling performance follows)")
	table.set_text("dlg.bard_show.outro.text", "en", "Well? Did you like it?")
	table.set_text("char.bard.name", "en", "Bard")
	table.set_text("ui.demo.hints", "ko", "이동: 방향키 · E: 대화 · K: 한/영")
	table.set_text("ui.demo.hints", "en", "Move: arrows · E: talk · K: KO/EN")
	table.set_text("ui.demo.prompt", "ko", "[E] 대화하기")
	table.set_text("ui.demo.prompt", "en", "[E] Talk")
	table.set_text("bark.tune.1", "ko", "♪ 라라라~")
	table.set_text("bark.tune.1", "en", "♪ La la la~")
	table.set_text("bark.tune.2", "ko", "♪ 오늘은 어떤 노래를 부를까…")
	table.set_text("bark.tune.2", "en", "♪ What shall I sing today...")
	db.localization_tables = [table]
	return db
