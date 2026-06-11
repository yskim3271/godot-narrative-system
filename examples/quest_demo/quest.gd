extends Node2D
## Quest Demo — 대화로 퀘스트를 수주하고, 월드에서 목표를 진행하고,
## 보고로 완료하는 전체 사이클 + 로그/트래커/알림 UI.
## 조작: 방향키 이동 · E 대화 · J 퀘스트 로그 · 약초(녹색)를 밟아 채집

const SPEED := 240.0
const TALK_DISTANCE := 96.0
const PICK_DISTANCE := 34.0

@onready var _player: Node2D = $Player
@onready var _npc: Node2D = $Npc
@onready var _prompt: Label = $Hud/Prompt
@onready var _quest_log: CanvasLayer = $QuestLog

var _herbs: Array[Node2D] = []


func _ready() -> void:
	for child in $Herbs.get_children():
		_herbs.append(child)
	Narrative.load_database(_build_database())
	Narrative.quest_updated.connect(func(_id: String) -> void: _sync_herbs())
	_sync_herbs()


func _process(delta: float) -> void:
	if Narrative.is_dialogue_running():
		_prompt.visible = false
		return
	_player.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * SPEED * delta
	_prompt.visible = _player.position.distance_to(_npc.position) < TALK_DISTANCE
	_check_herbs()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_E:
			if not Narrative.is_dialogue_running() \
					and _player.position.distance_to(_npc.position) < TALK_DISTANCE:
				Narrative.start_dialogue("healer_talk")
		KEY_J:
			_quest_log.toggle()


func _check_herbs() -> void:
	if not Narrative.is_quest_active("herb_quest"):
		return
	for herb in _herbs:
		if herb.visible and _player.position.distance_to(herb.position) < PICK_DISTANCE:
			Narrative.update_objective("herb_quest", "gather")
			Narrative.show_alert("약초 채집!")
			return  # quest_updated -> _sync_herbs가 숨김


## 약초 가시성은 objective 진행에서 파생 — 항상 데이터와 일치합니다.
func _sync_herbs() -> void:
	var gathered := 0
	if Narrative.is_ready():
		gathered = Narrative.context.quests.get_objective_count("herb_quest", "gather")
	if Narrative.is_quest_completed("herb_quest"):
		gathered = _herbs.size()
	for i in _herbs.size():
		_herbs[i].visible = i >= gathered


func _build_database() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()

	var healer := NarrativeCharacter.new()
	healer.id = "healer"
	healer.display_name = "약사"
	db.characters = [healer]

	var gold := NarrativeVariable.new()
	gold.id = "gold"
	gold.type = NarrativeVariable.Type.INT
	db.variables = [gold]

	var objective := NarrativeQuestObjective.new()
	objective.id = "gather"
	objective.description = "약초 채집"
	objective.target_count = 3
	var quest := NarrativeQuest.new()
	quest.id = "herb_quest"
	quest.title = "약초 수집"
	quest.description = "약사의 부탁: 들판의 약초 세 뿌리를 모아오자."
	quest.objectives = [objective]
	quest.rewards = "gold += 50\nalert(\"보상: 50골드\")"
	db.quests = [quest]

	var give := _node("give", "들판의 약초 세 뿌리만 모아다 주겠나?",
		"quest_state(\"herb_quest\") == \"inactive\"",
		"start_quest(\"herb_quest\")\nalert(\"퀘스트 시작: 약초 수집\")")
	give.next_node_id = "progress"
	var progress := _node("progress", "아직 약초가 모자라는군.",
		"is_quest_active(\"herb_quest\") and objective_count(\"herb_quest\", \"gather\") < 3", "")
	progress.next_node_id = "done"
	var done := _node("done", "고맙네! 약속한 보수일세.",
		"is_quest_active(\"herb_quest\") and objective_count(\"herb_quest\", \"gather\") >= 3",
		"complete_quest(\"herb_quest\")\nalert(\"퀘스트 완료: 약초 수집\")")
	done.next_node_id = "after"
	var after := _node("after", "덕분에 살았네. 또 보세.",
		"is_quest_completed(\"herb_quest\")", "")

	var dialogue := NarrativeDialogue.new()
	dialogue.id = "healer_talk"
	dialogue.start_node_id = "give"
	dialogue.nodes = [give, progress, done, after]
	db.dialogues = [dialogue]
	return db


## 조건-스킵 체인 패턴: 퀘스트 상태에 맞는 첫 노드가 표시됩니다.
func _node(id: String, text: String, conditions: String, actions: String) -> NarrativeDialogueNode:
	var node := NarrativeDialogueNode.new()
	node.id = id
	node.speaker_id = "healer"
	node.text = text
	node.conditions = conditions
	node.actions = actions
	return node
