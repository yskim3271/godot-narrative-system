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


## A database covering every runner/evaluator scenario the unit tests need.
## Variables: gold(int,10), met_guard(bool,false), hero_name(string,"Hero").
static func standard() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.characters = [make_character("guard", "Guard"), make_character("player", "Player")]
	db.variables = [
		make_int_var("gold", 10),
		make_bool_var("met_guard", false),
		make_string_var("hero_name", "Hero"),
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
		# firsttime: greeting variation via has_seen on itself
		make_dialogue("firsttime", "f1", [
			make_node("f1", {"conditions": "not has_seen(\"firsttime\", \"f1\")", "next": "f2", "text": "nice to meet you"}),
			make_node("f2", {"text": "you again"}),
		]),
	]
	return db


static func _chain_nodes(count: int) -> Array:
	var nodes: Array = []
	for i in range(1, count + 1):
		var next_id := "k%d" % (i + 1) if i < count else ""
		nodes.append(make_node("k%d" % i, {"next": next_id}))
	return nodes
