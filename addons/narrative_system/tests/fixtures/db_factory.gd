extends RefCounted
## Builds test databases in code. No .tres fixtures — files rot when classes
## change, code stays type-checked.


static func make_character(id: String, display_name := "") -> NarrativeCharacter:
	var character := NarrativeCharacter.new()
	character.id = id
	character.display_name = display_name if display_name != "" else id.capitalize()
	return character


static func make_int_var(id: String, value: int, persistent := true) -> NarrativeVariable:
	var variable := NarrativeVariable.new()
	variable.id = id
	variable.type = NarrativeVariable.Type.INT
	variable.default_int = value
	variable.persistent = persistent
	return variable


static func make_bool_var(id: String, value: bool) -> NarrativeVariable:
	var variable := NarrativeVariable.new()
	variable.id = id
	variable.type = NarrativeVariable.Type.BOOL
	variable.default_bool = value
	return variable


static func make_string_var(id: String, value: String) -> NarrativeVariable:
	var variable := NarrativeVariable.new()
	variable.id = id
	variable.type = NarrativeVariable.Type.STRING
	variable.default_string = value
	return variable


## opts: speaker, text, next, conditions, actions, choices (Array), key, seq
static func make_node(id: String, opts := {}) -> NarrativeDialogueNode:
	var node := NarrativeDialogueNode.new()
	node.id = id
	node.speaker_id = opts.get("speaker", "guard")
	node.text = opts.get("text", "line %s" % id)
	node.localized_text_key = opts.get("key", "")
	node.conditions = opts.get("conditions", "")
	node.actions = opts.get("actions", "")
	node.sequencer_commands = opts.get("seq", "")
	node.next_node_id = opts.get("next", "")
	var choices: Array[NarrativeChoice] = []
	for choice in opts.get("choices", []):
		choices.append(choice)
	node.choices = choices
	return node


## opts: text, condition, show_disabled, actions, target, key
static func make_choice(id: String, opts := {}) -> NarrativeChoice:
	var choice := NarrativeChoice.new()
	choice.id = id
	choice.text = opts.get("text", "choice %s" % id)
	choice.localized_text_key = opts.get("key", "")
	choice.condition = opts.get("condition", "")
	choice.show_disabled = opts.get("show_disabled", false)
	choice.actions = opts.get("actions", "")
	choice.target_node_id = opts.get("target", "")
	return choice


static func make_objective(id: String, target: int, description := "", initial := 0) -> NarrativeQuestObjective:
	var objective := NarrativeQuestObjective.new()
	objective.id = id
	objective.description = description if description != "" else "objective %s" % id
	objective.target_count = target
	objective.initial_count = initial
	return objective


## opts: title, description, objectives (Array), prerequisites (Array),
## rewards, auto_track
static func make_quest(id: String, opts := {}) -> NarrativeQuest:
	var quest := NarrativeQuest.new()
	quest.id = id
	quest.title = opts.get("title", "Quest %s" % id)
	quest.description = opts.get("description", "")
	var objectives: Array[NarrativeQuestObjective] = []
	for objective in opts.get("objectives", []):
		objectives.append(objective)
	quest.objectives = objectives
	var prerequisites := PackedStringArray()
	for prerequisite in opts.get("prerequisites", []):
		prerequisites.append(prerequisite)
	quest.prerequisites = prerequisites
	quest.rewards = opts.get("rewards", "")
	quest.auto_track = opts.get("auto_track", true)
	return quest


static func make_dialogue(id: String, start_node_id: String, nodes: Array) -> NarrativeDialogue:
	var dialogue := NarrativeDialogue.new()
	dialogue.id = id
	dialogue.title = id
	dialogue.start_node_id = start_node_id
	var typed: Array[NarrativeDialogueNode] = []
	for node in nodes:
		typed.append(node)
	dialogue.nodes = typed
	return dialogue


static func make_loc_table() -> NarrativeLocalizationTable:
	var table := NarrativeLocalizationTable.new()
	table.id = "main"
	table.set_text("greet.key", "en", "Hello")
	table.set_text("greet.key", "ko", "안녕하세요")
	table.set_text("dlg.linear.n1.text", "ko", "첫 번째")  # convention key, ko only
	table.set_text("quest.rats.title", "ko", "쥐 사냥")
	table.set_text("char.guard.name", "ko", "경비병")
	table.set_text("ui.quest_log.title", "ko", "퀘스트")
	table.set_text("ui.alert.reward", "en", "Reward!")
	table.set_text("ui.alert.reward", "ko", "보상!")
	table.set_text("only.korean", "ko", "한국어만")
	return table


## A database covering every runner/evaluator scenario the unit tests need.
## Variables: gold(int,10), met_guard(bool,false), hero_name(string,"Hero").
static func standard() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.localization_tables = [make_loc_table()]
	db.characters = [make_character("guard", "Guard"), make_character("player", "Player")]
	db.variables = [
		make_int_var("gold", 10),
		make_bool_var("met_guard", false),
		make_string_var("hero_name", "Hero"),
		make_int_var("session_tmp", 7, false),  # persistent = false: excluded from saves
	]
	db.quests = [
		make_quest("rats", {
			"title": "Rat Hunt",
			"description": "Clear the cellar.",
			"objectives": [make_objective("kill_rats", 5, "Kill cellar rats")],
			"rewards": "gold += 100\nalert(\"ui.alert.reward\")",
		}),
		make_quest("intro", {"title": "Meet the Guard"}),
		make_quest("after", {"title": "Afterparty", "prerequisites": ["intro"]}),
		make_quest("chain_a", {"rewards": "complete_quest(\"chain_b\")"}),
		make_quest("chain_b", {}),
		make_quest("untracked", {"auto_track": false}),
	]
	db.dialogues = [
		# linear: n1 -> n2 -> n3 -> end
		make_dialogue("linear", "n1", [
			make_node("n1", {"next": "n2", "text": "first"}),
			make_node("n2", {"next": "n3", "text": "second"}),
			make_node("n3", {"text": "third"}),
		]),
		# branch: choices with always/conditional-disabled/conditional-hidden
		make_dialogue("branch", "q", [
			make_node("q", {"text": "what do you do?", "choices": [
				make_choice("stay", {"target": "good", "actions": "met_guard = true"}),
				make_choice("bribe", {"condition": "gold >= 100", "show_disabled": true, "target": "rich"}),
				make_choice("secret", {"condition": "met_guard", "target": "hidden_path"}),
			]}),
			make_node("good", {"text": "good end"}),
			make_node("rich", {"text": "rich end"}),
			make_node("hidden_path", {"text": "secret end"}),
		]),
		# skipper: start node's condition is false -> hops to s2
		make_dialogue("skipper", "s1", [
			make_node("s1", {"conditions": "false", "next": "s2", "text": "skipped"}),
			make_node("s2", {"text": "landed"}),
		]),
		# cycle: condition-false nodes pointing at each other (hop guard)
		make_dialogue("cycle", "c1", [
			make_node("c1", {"conditions": "false", "next": "c2"}),
			make_node("c2", {"conditions": "false", "next": "c1"}),
		]),
		# broken: next_node_id points nowhere
		make_dialogue("broken", "b1", [
			make_node("b1", {"next": "missing_node", "text": "before the void"}),
		]),
		# chain: 12 auto-advanceable nodes for the re-entrancy drain test
		make_dialogue("chain", "k1", _chain_nodes(12)),
		# allhidden: a node whose only choices are all hidden
		make_dialogue("allhidden", "h1", [
			make_node("h1", {"text": "nothing to pick", "choices": [
				make_choice("never_a", {"condition": "false", "target": "h2"}),
				make_choice("never_b", {"condition": "false", "target": "h2"}),
			]}),
			make_node("h2", {"text": "unreachable by choice"}),
		]),
		# actions: node actions mutate variables before presentation
		make_dialogue("actions", "a1", [
			make_node("a1", {"actions": "gold += 5\nmet_guard = true", "next": "a2", "text": "paid"}),
			make_node("a2", {"text": "done"}),
		]),
		# seqtest: sequencer run that gets cancelled by advance()
		make_dialogue("seqtest", "s1", [
			make_node("s1", {"seq": "wait(0.3)\nset_variable(\"gold\", 99)", "next": "s2", "text": "watch this"}),
			make_node("s2", {"text": "interrupted"}),
		]),
		# loctest: explicit localization keys (existing + missing)
		make_dialogue("loctest", "L1", [
			make_node("L1", {"key": "greet.key", "text": "RAW greet", "next": "L2"}),
			make_node("L2", {"key": "missing.key", "text": "fallback line"}),
		]),
		# questgiver: starts/completes quests from dialogue actions
		make_dialogue("questgiver", "g1", [
			make_node("g1", {"actions": "start_quest(\"rats\")", "next": "g2", "text": "go kill rats"}),
			make_node("g2", {"conditions": "is_quest_active(\"rats\")", "text": "they await"}),
		]),
		# firsttime: greeting variation via has_seen on itself
		make_dialogue("firsttime", "f1", [
			make_node("f1", {"conditions": "not has_seen(\"firsttime\", \"f1\")", "next": "f2", "text": "nice to meet you"}),
			make_node("f2", {"text": "you again"}),
		]),
	]
	return db


## A small database that must validate with ZERO issues (errors or warnings).
static func clean() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.characters = [make_character("guard", "Guard")]
	db.variables = [make_int_var("gold", 10), make_bool_var("met_guard", false)]
	var table := NarrativeLocalizationTable.new()
	table.set_text("dlg.hello.h1.text", "ko", "안녕")
	db.localization_tables = [table]
	db.quests = [
		make_quest("intro", {"title": "Intro", "rewards": "gold += 5"}),
	]
	db.dialogues = [
		make_dialogue("hello", "h1", [
			make_node("h1", {"text": "hi", "conditions": "gold >= 0", "actions": "met_guard = true", "seq": "wait(0.1)", "next": "h2"}),
			make_node("h2", {"text": "pick", "choices": [
				make_choice("more", {"target": "h3", "actions": "start_quest(\"intro\")"}),
				make_choice("bye", {}),
			]}),
			make_node("h3", {"text": "extra"}),
		]),
	]
	return db


static func _chain_nodes(count: int) -> Array:
	var nodes: Array = []
	for i in range(1, count + 1):
		var next_id := "k%d" % (i + 1) if i < count else ""
		nodes.append(make_node("k%d" % i, {"next": next_id}))
	return nodes
