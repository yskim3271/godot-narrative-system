@tool
class_name NarrativeValidator
extends RefCounted
## Static analysis for a NarrativeDatabase. Editor-independent: used by the
## editor validation panel, the headless CLI (validate_cli.gd) and tests.
##
## Issue shape: { severity: "error"|"warning", code: String,
##                message: String, where: String }
##
## Errors are authoring bugs that will misbehave at runtime (broken links,
## unknown ids, parse failures, duplicate/shared resources). Warnings are
## smells the runtime tolerates (unreachable nodes, undeclared variables,
## missing localization keys, suspicious loops, id charset).

const Parser := preload("../runtime/dsl/parser.gd")

## Kept in sync with dsl/builtin_functions.gd.
const BUILTIN_FUNCTIONS: PackedStringArray = [
	"str", "has_seen", "quest_state", "is_quest_active", "is_quest_completed",
	"is_quest_failed", "start_quest", "complete_quest", "fail_quest",
	"update_objective", "objective_count", "set_expression", "alert",
]
## Kept in sync with runtime/builtin_commands.gd.
const BUILTIN_COMMANDS: PackedStringArray = [
	"wait", "play_animation", "play_animation_wait", "play_audio",
	"play_audio_wait", "move_camera", "focus_camera", "emit_signal",
	"call_method", "show_actor", "hide_actor", "set_expression",
	"set_variable", "start_quest", "complete_quest",
]
const QUEST_ID_FUNCTIONS: PackedStringArray = [
	"quest_state", "is_quest_active", "is_quest_completed", "is_quest_failed",
	"start_quest", "complete_quest", "fail_quest", "update_objective",
	"objective_count",
]

var _issues: Array[Dictionary] = []
var _db: NarrativeDatabase
var _parser := Parser.new()
var _id_regex := RegEx.create_from_string("^[a-zA-Z0-9_.]+$")
var _instance_first_seen: Dictionary = {}  # instance_id -> where
var _declared_vars: Dictionary = {}
var _known_functions: Dictionary = {}


func validate(db: NarrativeDatabase) -> Array[Dictionary]:
	_issues = []
	_instance_first_seen = {}
	_declared_vars = {}
	_known_functions = {}
	_db = db
	if db == null:
		_error("null_database", "database is null", "database")
		return _issues

	for name in BUILTIN_FUNCTIONS:
		_known_functions[name] = true
	for name in db.get_settings().declared_external_functions:
		_known_functions[name] = true
	for variable in db.variables:
		if variable != null:
			_declared_vars[variable.id] = true

	_check_id_list("characters", db.characters)
	_check_id_list("dialogues", db.dialogues)
	_check_id_list("quests", db.quests)
	_check_id_list("variables", db.variables)
	_check_quests()
	_check_dialogues()
	return _issues


static func count_severity(issues: Array[Dictionary], severity: String) -> int:
	var total := 0
	for issue in issues:
		if issue.severity == severity:
			total += 1
	return total


static func format_issue(issue: Dictionary) -> String:
	var tag := "ERROR" if issue.severity == "error" else "WARN "
	return "[%s] %s: %s  (%s)" % [tag, issue.code, issue.message, issue.where]


# --- category-level checks ---


func _check_id_list(category: String, items: Array) -> void:
	var seen := {}
	for i in items.size():
		var item: Resource = items[i]
		var where := "%s[%d]" % [category, i]
		if item == null:
			_warning("null_entry", "entry is null (delete it or assign a resource)", where)
			continue
		_check_shared_instance(item, where)
		var item_id: String = item.id
		if item_id == "":
			_error("empty_id", "entry has an empty id", where)
			continue
		where = "%s '%s'" % [category.trim_suffix("s"), item_id]
		_check_id_charset(item_id, where)
		if seen.has(item_id):
			_error("duplicate_id", "duplicate %s id '%s' (first definition wins at runtime)" % [category, item_id], where)
		seen[item_id] = true


func _check_quests() -> void:
	for quest in _db.quests:
		if quest == null or quest.id == "":
			continue
		var where := "quest '%s'" % quest.id
		for prerequisite in quest.prerequisites:
			if _db.get_quest(prerequisite) == null:
				_error("unknown_quest_id", "prerequisite '%s' does not exist" % prerequisite, where)
		var objective_ids := {}
		for objective in quest.objectives:
			if objective == null:
				_warning("null_entry", "objective entry is null", where)
				continue
			_check_shared_instance(objective, where)
			if objective.id == "":
				_error("empty_id", "objective has an empty id", where)
				continue
			if objective_ids.has(objective.id):
				_error("duplicate_id", "duplicate objective id '%s'" % objective.id, where)
			objective_ids[objective.id] = true
			_check_id_charset(objective.id, "%s > objective '%s'" % [where, objective.id])
			if objective.target_count < 1:
				_warning("invalid_target_count", "objective '%s' target_count is %d (minimum 1)" % [objective.id, objective.target_count], where)
			_check_loc_key(objective.description_key, "%s > objective '%s'" % [where, objective.id])
		_check_loc_key(quest.title_key, where)
		_check_loc_key(quest.description_key, where)
		_check_dsl(quest.rewards, "actions", "%s > rewards" % where)


func _check_dialogues() -> void:
	for dialogue in _db.dialogues:
		if dialogue == null or dialogue.id == "":
			continue
		_check_one_dialogue(dialogue)


func _check_one_dialogue(dialogue: NarrativeDialogue) -> void:
	var dialogue_where := "dialogue '%s'" % dialogue.id
	var node_ids := {}
	for node in dialogue.nodes:
		if node == null:
			_warning("null_entry", "node entry is null", dialogue_where)
			continue
		_check_shared_instance(node, dialogue_where)
		if node.id == "":
			_error("empty_id", "node has an empty id", dialogue_where)
			continue
		if node_ids.has(node.id):
			_error("duplicate_id", "duplicate node id '%s'" % node.id, dialogue_where)
		node_ids[node.id] = true

	# start node
	if dialogue.start_node_id == "":
		_error("missing_start_node", "start_node_id is empty", dialogue_where)
	elif not node_ids.has(dialogue.start_node_id):
		_error("missing_start_node", "start_node_id '%s' does not exist" % dialogue.start_node_id, dialogue_where)

	# per-node checks
	for node in dialogue.nodes:
		if node == null or node.id == "":
			continue
		var where := "%s > node '%s'" % [dialogue_where, node.id]
		_check_id_charset(node.id, where)
		if node.speaker_id != "" and _db.get_character(node.speaker_id) == null:
			_error("unknown_character_id", "speaker_id '%s' does not exist" % node.speaker_id, where)
		if node.next_node_id != "" and not node_ids.has(node.next_node_id):
			_error("broken_link", "next_node_id '%s' does not exist" % node.next_node_id, where)
		_check_loc_key(node.localized_text_key, where)
		_check_dsl(node.conditions, "condition", where + " > conditions")
		_check_dsl(node.actions, "actions", where + " > actions")
		_check_dsl(node.sequencer_commands, "sequence", where + " > sequence")

		var choice_ids := {}
		for choice in node.choices:
			if choice == null:
				_warning("null_entry", "choice entry is null", where)
				continue
			_check_shared_instance(choice, where)
			if choice.id == "":
				_error("empty_id", "choice has an empty id", where)
				continue
			var choice_where := "%s > choice '%s'" % [where, choice.id]
			if choice_ids.has(choice.id):
				_error("duplicate_id", "duplicate choice id '%s'" % choice.id, where)
			choice_ids[choice.id] = true
			if choice.target_node_id != "" and not node_ids.has(choice.target_node_id):
				_error("broken_link", "choice target '%s' does not exist" % choice.target_node_id, choice_where)
			_check_loc_key(choice.localized_text_key, choice_where)
			_check_dsl(choice.condition, "condition", choice_where + " > condition")
			_check_dsl(choice.actions, "actions", choice_where + " > actions")

	_check_reachability(dialogue, node_ids, dialogue_where)
	_check_condition_skip_cycles(dialogue, dialogue_where)


func _check_reachability(dialogue: NarrativeDialogue, node_ids: Dictionary, dialogue_where: String) -> void:
	if not node_ids.has(dialogue.start_node_id):
		return  # already reported
	var reached := {}
	var frontier: Array[String] = [dialogue.start_node_id]
	while not frontier.is_empty():
		var node_id: String = frontier.pop_back()
		if reached.has(node_id):
			continue
		reached[node_id] = true
		var node := dialogue.get_node_by_id(node_id)
		if node == null:
			continue
		if node.next_node_id != "" and node_ids.has(node.next_node_id):
			frontier.append(node.next_node_id)
		for choice in node.choices:
			if choice != null and choice.target_node_id != "" and node_ids.has(choice.target_node_id):
				frontier.append(choice.target_node_id)
	for node in dialogue.nodes:
		if node != null and node.id != "" and not reached.has(node.id):
			_warning("unreachable_node", "node '%s' cannot be reached from the start node" % node.id, dialogue_where)


## Cycles along next_node_id where EVERY node has a condition can skip
## forever at runtime (the hop guard ends the dialogue, but it is almost
## certainly an authoring mistake).
func _check_condition_skip_cycles(dialogue: NarrativeDialogue, dialogue_where: String) -> void:
	var reported := {}
	for start in dialogue.nodes:
		if start == null or start.id == "" or reported.has(start.id):
			continue
		if start.conditions.strip_edges() == "":
			continue
		var path: Array[String] = []
		var node := start
		while node != null and node.conditions.strip_edges() != "" and node.next_node_id != "":
			if path.has(node.id):
				var cycle := path.slice(path.find(node.id))
				for node_id in cycle:
					reported[node_id] = true
				_warning(
					"suspicious_loop",
					"condition-skip cycle: %s — if all conditions are false this loops until max_node_hops" % " -> ".join(cycle),
					dialogue_where
				)
				break
			path.append(node.id)
			node = dialogue.get_node_by_id(node.next_node_id)


# --- DSL static analysis ---


func _check_dsl(source: String, mode: String, where: String) -> void:
	if source.strip_edges() == "":
		return
	var parsed: Dictionary
	match mode:
		"condition":
			parsed = _parser.parse_condition(source)
		"actions":
			parsed = _parser.parse_actions(source)
		_:
			parsed = _parser.parse_sequence(source)
	if not parsed.ok:
		_error("dsl_parse_error", "parse error at %d: %s" % [parsed.error.pos, parsed.error.message], where)
		return
	if mode == "condition":
		_walk_expr(parsed.ast, where)
		return
	for stmt in parsed.statements:
		if str(stmt[0]) == "assign":
			if not _declared_vars.has(str(stmt[2])):
				_warning("undeclared_variable", "assignment to undeclared variable '%s' (creates a transient variable)" % str(stmt[2]), where)
			_walk_expr(stmt[3], where)
		else:  # call
			_check_call(stmt, where, mode == "sequence")


func _walk_expr(ast: Array, where: String) -> void:
	match str(ast[0]):
		"lit":
			pass
		"var":
			if not _declared_vars.has(str(ast[1])):
				_warning("undeclared_variable", "variable '%s' is not declared in the database (reads as null)" % str(ast[1]), where)
		"not", "neg":
			_walk_expr(ast[1], where)
		"and", "or":
			_walk_expr(ast[1], where)
			_walk_expr(ast[2], where)
		"bin":
			_walk_expr(ast[2], where)
			_walk_expr(ast[3], where)
		"call":
			_check_call(ast, where, false)


func _check_call(call_ast: Array, where: String, as_command: bool) -> void:
	var name := str(call_ast[1])
	var args: Array = call_ast[2]
	if as_command:
		if not BUILTIN_COMMANDS.has(name) and not _known_functions.has(name):
			_warning("unknown_command", "sequencer command '%s' is not built-in (runtime skips unknown commands; declare it in settings.declared_external_functions if registered by code)" % name, where)
	elif not _known_functions.has(name):
		_error("unknown_function", "function '%s' is not built-in (declare it in settings.declared_external_functions if registered by code)" % name, where)

	# literal-argument id checks
	if QUEST_ID_FUNCTIONS.has(name) and _lit_string(args, 0) != "":
		var quest_id := _lit_string(args, 0)
		var quest := _db.get_quest(quest_id)
		if quest == null:
			_error("unknown_quest_id", "%s('%s') — quest does not exist" % [name, quest_id], where)
		elif name in ["update_objective", "objective_count"] and _lit_string(args, 1) != "" and quest.get_objective_by_id(_lit_string(args, 1)) == null:
			_error("unknown_objective_id", "quest '%s' has no objective '%s'" % [quest_id, _lit_string(args, 1)], where)
	if name == "has_seen" and _lit_string(args, 0) != "":
		var dialogue := _db.get_dialogue(_lit_string(args, 0))
		if dialogue == null:
			_error("unknown_dialogue_id", "has_seen('%s') — dialogue does not exist" % _lit_string(args, 0), where)
		elif args.size() >= 2 and _lit_string(args, 1) != "" and not dialogue.has_node_id(_lit_string(args, 1)):
			_error("unknown_node_id", "has_seen('%s', '%s') — node does not exist" % [_lit_string(args, 0), _lit_string(args, 1)], where)
	if name == "set_expression" and _lit_string(args, 0) != "" and _db.get_character(_lit_string(args, 0)) == null:
		_error("unknown_character_id", "set_expression('%s') — character does not exist" % _lit_string(args, 0), where)

	for arg in args:
		_walk_expr(arg, where)


func _lit_string(args: Array, index: int) -> String:
	if index < args.size() and str(args[index][0]) == "lit" and typeof(args[index][1]) == TYPE_STRING:
		return args[index][1]
	return ""


# --- shared helpers ---


func _check_loc_key(key: String, where: String) -> void:
	if key == "":
		return
	for table in _db.localization_tables:
		if table != null and table.entries.has(key):
			return
	_warning("missing_localization_key", "localization key '%s' is not in any table (falls back to inline text)" % key, where)


func _check_id_charset(id: String, where: String) -> void:
	if _id_regex.search(id) == null:
		_warning("id_charset", "id '%s' contains characters outside [a-zA-Z0-9_.] — unsafe in keys and saves" % id, where)


func _check_shared_instance(resource: Resource, where: String) -> void:
	var key := resource.get_instance_id()
	if _instance_first_seen.has(key):
		_error(
			"shared_resource_instance",
			"this resource instance also appears at %s — Inspector array duplication shares the instance; use 'Make Unique'" % _instance_first_seen[key],
			where
		)
		return
	_instance_first_seen[key] = where


func _error(code: String, message: String, where: String) -> void:
	_issues.append({"severity": "error", "code": code, "message": message, "where": where})


func _warning(code: String, message: String, where: String) -> void:
	_issues.append({"severity": "warning", "code": code, "message": message, "where": where})
