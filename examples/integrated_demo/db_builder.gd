extends RefCounted
## Source of truth for the demo database. demo_database.tres is generated
## from this builder (run regenerate_db.gd after editing) so the committed
## resource never drifts from the authored content.
##
## Authoring language: Korean inline text (default_language = "ko"),
## English via convention keys in the localization table.


static func build() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.settings = NarrativeSettings.new()
	db.settings.default_language = "ko"
	db.settings.fallback_language = "en"

	# --- characters ---
	var guard := NarrativeCharacter.new()
	guard.id = "guard"
	guard.display_name = "경비병"
	guard.portrait = _portrait(Color(0.72, 0.34, 0.3), Color(0.32, 0.13, 0.12))
	guard.expressions = {
		"happy": _portrait(Color(0.93, 0.74, 0.32), Color(0.45, 0.33, 0.1)),
		"angry": _portrait(Color(0.88, 0.18, 0.18), Color(0.3, 0.05, 0.05)),
	}
	var player := NarrativeCharacter.new()
	player.id = "player"
	player.display_name = "나"
	player.portrait = _portrait(Color(0.3, 0.5, 0.85), Color(0.1, 0.18, 0.35))
	db.characters = [guard, player]

	# --- variables ---
	var gold := NarrativeVariable.new()
	gold.id = "gold"
	gold.type = NarrativeVariable.Type.INT
	gold.default_int = 30
	var met := NarrativeVariable.new()
	met.id = "met_guard"
	met.type = NarrativeVariable.Type.BOOL
	db.variables = [gold, met]

	# --- quest ---
	var objective := NarrativeQuestObjective.new()
	objective.id = "kill_rats"
	objective.description = "지하실 쥐 처치"
	objective.target_count = 5
	var quest := NarrativeQuest.new()
	quest.id = "rat_hunt"
	quest.title = "쥐 사냥"
	quest.description = "경비병의 부탁: 지하실에 들끓는 쥐를 정리하자."
	quest.objectives = [objective]
	quest.rewards = "gold += 100\nalert(\"ui.alert.reward_gold\")"
	db.quests = [quest]

	# --- dialogue ---
	db.dialogues = [_guard_dialogue()]

	# --- localization (en translations + bilingual UI strings) ---
	db.localization_tables = [_localization()]
	return db


static func _guard_dialogue() -> NarrativeDialogue:
	# First-visit variation pattern: the start node shows the RETURN greeting
	# (condition: g_first was seen) and otherwise skips to the first-time
	# greeting. Both funnel into the menu node.
	var g_return := _node("g_return", "또 자네군. 무슨 일이지?", {
		"conditions": "has_seen(\"guard_talk\", \"g_first\")",
		"next": "g_first",
	})
	var g_first := _node("g_first", "처음 보는 얼굴이군. 이 마을엔 무슨 일로 왔나?", {
		"conditions": "not has_seen(\"guard_talk\", \"g_first\")",
		"next": "g_menu",
		"seq": "set_expression(\"guard\", \"angry\")",
	})
	var g_menu := _node("g_menu", "용건을 말해보게.", {
		"seq": "set_expression(\"guard\", \"\")",
	})
	g_menu.choices = [
		_choice("c_quest", "일거리가 있나?", {
			"condition": "quest_state(\"rat_hunt\") == \"inactive\"",
			"target": "q_give",
		}),
		_choice("c_progress", "쥐는 잡는 중이야.", {
			"condition": "is_quest_active(\"rat_hunt\") and objective_count(\"rat_hunt\", \"kill_rats\") < 5",
			"target": "q_progress",
		}),
		_choice("c_done", "쥐를 모두 처리했네.", {
			"condition": "is_quest_active(\"rat_hunt\") and objective_count(\"rat_hunt\", \"kill_rats\") >= 5",
			"target": "q_done",
		}),
		_choice("c_bribe", "통행료를 내겠네. (50골드)", {
			"condition": "gold >= 50",
			"show_disabled": true,
			"actions": "gold -= 50\nmet_guard = true",
			"target": "q_bribe",
		}),
		_choice("c_bye", "아무것도 아닐세.", {}),
	]
	var q_give := _node("q_give", "지하실에 쥐가 들끓고 있네. 다섯 마리만 잡아주게.", {
		"actions": "start_quest(\"rat_hunt\")\nalert(\"ui.alert.quest_started\")",
		"seq": "set_expression(\"guard\", \"happy\")\nplay_animation(\"guard\", \"wave\")\nwait(0.5)\nfocus_camera(\"guard\", 0.4)\nemit_signal(\"quest_given\")\nwait(0.6)\nmove_camera(0, 0, 0.4)",
	})
	var q_progress := _node("q_progress", "서둘러 주게. 쥐들이 곡식을 다 먹어치우고 있어.", {})
	var q_done := _node("q_done", "훌륭하군! 약속한 보수일세.", {
		"actions": "complete_quest(\"rat_hunt\")\nalert(\"ui.alert.quest_done\")",
		"seq": "set_expression(\"guard\", \"happy\")\nplay_animation(\"guard\", \"wave\")",
	})
	var q_bribe := _node("q_bribe", "흠… 좋아, 지나가게.", {
		"seq": "set_expression(\"guard\", \"happy\")",
	})

	var dialogue := NarrativeDialogue.new()
	dialogue.id = "guard_talk"
	dialogue.title = "경비병 대화"
	dialogue.start_node_id = "g_return"
	dialogue.nodes = [g_return, g_first, g_menu, q_give, q_progress, q_done, q_bribe]
	return dialogue


static func _localization() -> NarrativeLocalizationTable:
	var t := NarrativeLocalizationTable.new()
	t.id = "demo"
	# English translations of the Korean inline lines (convention keys)
	t.set_text("dlg.guard_talk.g_return.text", "en", "You again. What is it?")
	t.set_text("dlg.guard_talk.g_first.text", "en", "A new face. What brings you to this town?")
	t.set_text("dlg.guard_talk.g_menu.text", "en", "State your business.")
	t.set_text("dlg.guard_talk.q_give.text", "en", "The cellar is crawling with rats. Deal with five of them, will you?")
	t.set_text("dlg.guard_talk.q_progress.text", "en", "Hurry. They are eating through our grain.")
	t.set_text("dlg.guard_talk.q_done.text", "en", "Splendid! Here is the pay I promised.")
	t.set_text("dlg.guard_talk.q_bribe.text", "en", "Hm... fine, move along.")
	t.set_text("dlg.guard_talk.g_menu.choice.c_quest", "en", "Got any work?")
	t.set_text("dlg.guard_talk.g_menu.choice.c_progress", "en", "Still hunting the rats.")
	t.set_text("dlg.guard_talk.g_menu.choice.c_done", "en", "The rats are dealt with.")
	t.set_text("dlg.guard_talk.g_menu.choice.c_bribe", "en", "I will pay the toll. (50 gold)")
	t.set_text("dlg.guard_talk.g_menu.choice.c_bye", "en", "Never mind.")
	t.set_text("char.guard.name", "en", "Guard")
	t.set_text("char.player.name", "en", "Me")
	t.set_text("quest.rat_hunt.title", "en", "Rat Hunt")
	t.set_text("quest.rat_hunt.desc", "en", "The guard's request: clear out the rats infesting the cellar.")
	t.set_text("quest.rat_hunt.obj.kill_rats", "en", "Clear cellar rats")
	# Bilingual UI / alert / bark strings (key-only content)
	_pair(t, "ui.alert.quest_started", "퀘스트 시작: 쥐 사냥", "Quest started: Rat Hunt")
	_pair(t, "ui.alert.quest_done", "퀘스트 완료: 쥐 사냥", "Quest completed: Rat Hunt")
	_pair(t, "ui.alert.reward_gold", "보상: 100 골드", "Reward: 100 gold")
	_pair(t, "ui.alert.rat", "쥐 처치!", "Rat down!")
	_pair(t, "ui.alert.saved", "저장됨 (F9로 불러오기)", "Saved (F9 to load)")
	_pair(t, "ui.alert.loaded", "불러옴", "Loaded")
	_pair(t, "ui.quest_log.title", "퀘스트", "Quests")
	_pair(t, "ui.quest_log.active", "진행 중", "Active")
	_pair(t, "ui.quest_log.completed", "완료", "Completed")
	_pair(t, "ui.quest_log.failed", "실패", "Failed")
	_pair(t, "ui.quest_log.track", "트래커에 표시", "Show in tracker")
	_pair(t, "ui.demo.hints", "이동: 방향키 · E: 대화 · J: 퀘스트 로그 · K: 한/영 · F5: 저장 · F9: 불러오기", "Move: arrows · E: talk · J: quest log · K: KO/EN · F5: save · F9: load")
	_pair(t, "ui.demo.prompt", "[E] 대화하기", "[E] Talk")
	_pair(t, "ui.demo.gold", "골드", "Gold")
	_pair(t, "bark.idle.1", "오늘도 평화롭군.", "Peaceful day, as always.")
	_pair(t, "bark.idle.2", "지하실 쪽에서 소리가 나는군…", "I hear noises from the cellar...")
	_pair(t, "bark.idle.3", "경계를 늦추지 말 것.", "Stay alert.")
	return t


static func _pair(t: NarrativeLocalizationTable, key: String, ko: String, en: String) -> void:
	t.set_text(key, "ko", ko)
	t.set_text(key, "en", en)


static func _node(id: String, text: String, opts: Dictionary) -> NarrativeDialogueNode:
	var node := NarrativeDialogueNode.new()
	node.id = id
	node.speaker_id = opts.get("speaker", "guard")
	node.text = text
	node.conditions = opts.get("conditions", "")
	node.actions = opts.get("actions", "")
	node.sequencer_commands = opts.get("seq", "")
	node.next_node_id = opts.get("next", "")
	return node


static func _choice(id: String, text: String, opts: Dictionary) -> NarrativeChoice:
	var choice := NarrativeChoice.new()
	choice.id = id
	choice.text = text
	choice.condition = opts.get("condition", "")
	choice.show_disabled = opts.get("show_disabled", false)
	choice.actions = opts.get("actions", "")
	choice.target_node_id = opts.get("target", "")
	return choice


static func _portrait(fill: Color, edge: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([fill, edge])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.4)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 96
	texture.height = 96
	return texture
