extends Node
## Autoload facade for the Narrative System (registered as "Narrative").
##
## Game code talks to this node only: it re-emits every subsystem signal
## under the same name and delegates the public API to the context. The
## runtime also works without this autoload — build a NarrativeContext
## directly and pass it to UIs via their setup() method.
##
## NOTE: deliberately no class_name (it would collide with the autoload name).

signal dialogue_started(dialogue_id: String)
signal dialogue_resumed(dialogue_id: String, node_id: String)
signal node_entered(node_id: String)
signal line_presented(speaker_id: String, text: String)
signal choices_presented(choices: Array)
signal choice_selected(choice_id: String)
signal dialogue_ended(dialogue_id: String)
signal expression_changed(character_id: String, expression: String)
signal variable_changed(variable_id: String, value: Variant)
signal quest_updated(quest_id: String)
signal language_changed(locale: String)
signal alert_requested(text: String)
signal bark_requested(character_id: String, text: String, attach_to: Node)
signal sequence_event(event_name: String, args: Array)

const SETTING_DATABASE_PATH := "narrative_system/database_path"

var context: NarrativeContext


## True once a database is loaded. UIs use this to skip initial state pulls
## when auto-binding to a not-yet-configured autoload.
func is_ready() -> bool:
	return context != null


func _ready() -> void:
	var path := str(ProjectSettings.get_setting(SETTING_DATABASE_PATH, ""))
	if path == "":
		# Project not configured yet — stay idle until load_database() is called.
		return
	if not ResourceLoader.exists(path):
		push_error("Narrative: configured database not found at '%s' (project setting %s)" % [path, SETTING_DATABASE_PATH])
		return
	var db := load(path) as NarrativeDatabase
	if db == null:
		push_error("Narrative: resource at '%s' is not a NarrativeDatabase" % path)
		return
	load_database(db)


## Replaces the active database (rebuilds the whole context). Not legal while
## a dialogue is running.
func load_database(db: NarrativeDatabase) -> bool:
	if context != null and context.runner.is_dialogue_running():
		push_error("Narrative: cannot replace the database while a dialogue is running")
		return false
	context = NarrativeContext.create(db, get_tree())
	_wire(context)
	return true


# --- dialogue API ---


func start_dialogue(dialogue_id: String, start_node_id := "") -> bool:
	return context.runner.start_dialogue(dialogue_id, start_node_id) if _ok() else false


func advance() -> bool:
	return context.runner.advance() if _ok() else false


func select_choice(choice_id: String) -> bool:
	return context.runner.select_choice(choice_id) if _ok() else false


func end_dialogue() -> bool:
	return context.runner.end_dialogue() if _ok() else false


func get_current_node() -> NarrativeDialogueNode:
	return context.runner.get_current_node() if _ok() else null


func get_available_choices() -> Array[Dictionary]:
	return context.runner.get_available_choices() if _ok() else []


func is_dialogue_running() -> bool:
	return context != null and context.runner.is_dialogue_running()


func is_waiting_for_choice() -> bool:
	return context != null and context.runner.is_waiting_for_choice()


func get_current_dialogue_id() -> String:
	return context.runner.get_current_dialogue_id() if _ok() else ""


func get_current_line_text() -> String:
	return context.runner.get_current_line_text() if _ok() else ""


func get_character(character_id: String) -> NarrativeCharacter:
	return context.runner.get_character(character_id) if _ok() else null


func get_character_display_name(character_id: String) -> String:
	return context.runner.get_character_display_name(character_id) if _ok() else character_id


# --- variables ---


func get_variable(variable_id: String) -> Variant:
	if not _ok():
		return null
	if not context.state.has_value(variable_id):
		push_warning("Narrative: get_variable('%s') — variable does not exist" % variable_id)
		return null
	return context.state.get_value(variable_id)


func has_variable(variable_id: String) -> bool:
	return context != null and context.state.has_value(variable_id)


func set_variable(variable_id: String, value: Variant) -> bool:
	if not _ok():
		return false
	var result := context.state.set_value(variable_id, value)
	if not result.ok:
		push_error("Narrative: set_variable failed — %s" % str(result.error))
		return false
	if result.has("warning"):
		push_warning("Narrative: %s" % str(result.warning))
	return true


# --- save / load ---


## Saves the whole narrative state to user://saves/<slot>.json.
## Returns OK, or ERR_BUSY when called from inside a dialogue transition.
func save_game(slot := "save") -> Error:
	return context.save_manager.save_game(slot) if _ok() else ERR_UNCONFIGURED


## Loads a slot, restores state and resumes the saved dialogue position.
func load_game(slot := "save") -> Error:
	return context.save_manager.load_game(slot) if _ok() else ERR_UNCONFIGURED


func has_save(slot := "save") -> bool:
	return context != null and context.save_manager.has_save(slot)


func delete_save(slot := "save") -> bool:
	return context != null and context.save_manager.delete_save(slot)


# --- DSL extension ---


## Exposes a game function to dialogue conditions/actions
## (see docs/dsl.md — return values must be null/bool/int/float/String).
func register_function(name: String, callable: Callable, override := false) -> bool:
	return context.evaluator.functions.register(name, callable, override) if _ok() else false


## Registers a custom sequencer command: callable(args: Array), may await.
func register_sequencer_command(name: String, handler: Callable, override := false) -> bool:
	return context.sequencer.register_command(name, handler, override) if _ok() else false


## Plays a sequencer command string directly (outside any dialogue node).
func play_sequence(source: String, label := "api") -> void:
	if _ok():
		context.sequencer.start_run(source, label)


# --- localization ---


func set_language(locale: String) -> void:
	if _ok():
		context.localization.set_language(locale)


func get_language() -> String:
	return context.localization.get_language() if _ok() else ""


## UI chrome text: localized "ui.*" key when present, else the fallback.
func get_ui_text(key: String, fallback := "") -> String:
	return context.localization.text_or(key, fallback) if _ok() else fallback


# --- quests ---


func start_quest(quest_id: String) -> bool:
	return context.quests.start_quest(quest_id) if _ok() else false


func complete_quest(quest_id: String, force := false) -> bool:
	return context.quests.complete_quest(quest_id, force) if _ok() else false


func fail_quest(quest_id: String) -> bool:
	return context.quests.fail_quest(quest_id) if _ok() else false


func update_objective(quest_id: String, objective_id: String, delta := 1) -> bool:
	return context.quests.update_objective(quest_id, objective_id, delta) if _ok() else false


func get_quest_state(quest_id: String) -> String:
	return context.quests.get_quest_state(quest_id) if _ok() else "inactive"


func is_quest_active(quest_id: String) -> bool:
	return context != null and context.quests.is_quest_active(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return context != null and context.quests.is_quest_completed(quest_id)


func is_quest_failed(quest_id: String) -> bool:
	return context != null and context.quests.is_quest_failed(quest_id)


func get_quests_in_state(state: String) -> Array[String]:
	return context.quests.get_quests_in_state(state) if _ok() else []


func get_tracked_quests() -> Array[String]:
	return context.quests.get_tracked_quests() if _ok() else []


func set_quest_tracked(quest_id: String, tracked: bool) -> bool:
	return context.quests.set_tracked(quest_id, tracked) if _ok() else false


func is_quest_tracked(quest_id: String) -> bool:
	return context != null and context.quests.is_tracked(quest_id)


func get_quest_title(quest_id: String) -> String:
	return context.quests.get_quest_title(quest_id) if _ok() else quest_id


func get_quest_description(quest_id: String) -> String:
	return context.quests.get_quest_description(quest_id) if _ok() else ""


func get_objectives_progress(quest_id: String) -> Array[Dictionary]:
	return context.quests.get_objectives_progress(quest_id) if _ok() else []


func are_all_objectives_completed(quest_id: String) -> bool:
	return context != null and context.quests.are_all_objectives_completed(quest_id)


# --- alerts / barks ---


func show_alert(text_or_key: String) -> void:
	if _ok():
		context.request_alert(text_or_key)


func bark(character_id: String, text_or_key: String, attach_to: Node = null) -> void:
	if _ok():
		context.bark(character_id, text_or_key, attach_to)


# --- actors ---


func register_actor(actor_id: String, node: Node) -> void:
	if _ok():
		context.register_actor(actor_id, node)


func unregister_actor(actor_id: String) -> void:
	if context != null:
		context.unregister_actor(actor_id)


func get_actor(actor_id: String) -> Node:
	return context.get_actor(actor_id) if _ok() else null


# --- internals ---


func _ok() -> bool:
	if context == null:
		push_error("Narrative: no database loaded — set the '%s' project setting or call load_database()" % SETTING_DATABASE_PATH)
		return false
	return true


func _wire(ctx: NarrativeContext) -> void:
	ctx.runner.dialogue_started.connect(func(id: String) -> void: dialogue_started.emit(id))
	ctx.runner.dialogue_resumed.connect(func(id: String, node_id: String) -> void: dialogue_resumed.emit(id, node_id))
	ctx.runner.node_entered.connect(func(id: String) -> void: node_entered.emit(id))
	ctx.runner.line_presented.connect(func(speaker: String, text: String) -> void: line_presented.emit(speaker, text))
	ctx.runner.choices_presented.connect(func(choices: Array) -> void: choices_presented.emit(choices))
	ctx.runner.choice_selected.connect(func(id: String) -> void: choice_selected.emit(id))
	ctx.runner.dialogue_ended.connect(func(id: String) -> void: dialogue_ended.emit(id))
	ctx.runner.expression_changed.connect(func(c: String, e: String) -> void: expression_changed.emit(c, e))
	ctx.state.variable_changed.connect(func(id: String, value: Variant) -> void: variable_changed.emit(id, value))
	ctx.localization.language_changed.connect(func(locale: String) -> void: language_changed.emit(locale))
	ctx.alert_requested.connect(func(text: String) -> void: alert_requested.emit(text))
	ctx.bark_requested.connect(func(c: String, t: String, n: Node) -> void: bark_requested.emit(c, t, n))
	ctx.sequencer.sequence_event.connect(func(event_name: String, args: Array) -> void: sequence_event.emit(event_name, args))
	if ctx.quests != null:
		ctx.quests.quest_updated.connect(func(id: String) -> void: quest_updated.emit(id))
