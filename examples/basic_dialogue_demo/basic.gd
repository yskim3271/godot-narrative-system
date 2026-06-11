extends Node2D
## Basic Dialogue Demo — 가장 작은 구성: 코드로 만든 데이터베이스 + NPC 하나 +
## 선형 대화. getting_started.md의 최소 예제에 해당합니다.
## 조작: 방향키 이동 · E 대화 · Enter/Space/클릭 진행

const SPEED := 240.0
const TALK_DISTANCE := 96.0

@onready var _player: Node2D = $Player
@onready var _npc: Node2D = $Npc
@onready var _prompt: Label = $Hud/Prompt


func _ready() -> void:
	Narrative.load_database(_build_database())


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
		Narrative.start_dialogue("hello")


func _build_database() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()

	var elder := NarrativeCharacter.new()
	elder.id = "elder"
	elder.display_name = "촌장"
	db.characters = [elder]

	var n1 := NarrativeDialogueNode.new()
	n1.id = "n1"
	n1.speaker_id = "elder"
	n1.text = "어서 오게, 여행자여."
	n1.next_node_id = "n2"
	var n2 := NarrativeDialogueNode.new()
	n2.id = "n2"
	n2.speaker_id = "elder"
	n2.text = "이 마을은 작지만 평화로운 곳이라네."
	n2.next_node_id = "n3"
	var n3 := NarrativeDialogueNode.new()
	n3.id = "n3"
	n3.speaker_id = "elder"
	n3.text = "편히 쉬다 가게."  # next 비움 = 대화 종료

	var dialogue := NarrativeDialogue.new()
	dialogue.id = "hello"
	dialogue.start_node_id = "n1"
	dialogue.nodes = [n1, n2, n3]
	db.dialogues = [dialogue]
	return db
