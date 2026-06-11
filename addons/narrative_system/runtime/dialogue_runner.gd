class_name NarrativeDialogueRunner
extends RefCounted
## Drives a dialogue graph: node transitions, condition gating, actions,
## choice handling and presentation signals. Fully headless — UIs are plain
## signal subscribers.
##
## Re-entrancy: while a transition is processing (_busy), mutator calls
## (advance/select_choice/end_dialogue) are queued in a single-slot pending
## queue and drained iteratively, so auto-advancing dialogues cannot grow
## the stack and signal handlers may safely call back into the runner.

signal dialogue_started(dialogue_id: String)
signal dialogue_resumed(dialogue_id: String, node_id: String)
signal node_entered(node_id: String)
signal line_presented(speaker_id: String, text: String)
signal choices_presented(choices: Array)
signal choice_selected(choice_id: String)
signal dialogue_ended(dialogue_id: String)
signal expression_changed(character_id: String, expression: String)

enum Phase { IDLE, AT_LINE, AT_CHOICES }

const Evaluator := preload("dsl/evaluator.gd")
const TextMarkup := preload("text_markup.gd")

var _database: NarrativeDatabase
var _state: NarrativeState
var _evaluator: Evaluator
var _localization: NarrativeLocalizationManager
var _sequencer = null  # NarrativeSequencer, attached in Phase 6
var _max_hops := 64

var _phase := Phase.IDLE
var _dialogue: NarrativeDialogue
var _node: NarrativeDialogueNode
var _visible: Array[Dictionary] = []  # [{choice: NarrativeChoice, enabled: bool}]
var _busy := false
var _pending: Array[Dictionary] = []


func setup(
	database: NarrativeDatabase,
	state: NarrativeState,
	evaluator: Evaluator,
	localization: NarrativeLocalizationManager,
) -> void:
	_database = database
	_state = state
	_evaluator = evaluator
	_localization = localization
	_max_hops = database.get_settings().max_node_hops


func set_sequencer(sequencer) -> void:
	_sequencer = sequencer


# --- public API ---


## Starts a dialogue at its start node (or an explicit node). Returns false
## with a descriptive error when the dialogue cannot start.
func start_dialogue(dialogue_id: String, start_node_id := "") -> bool:
	if _busy:
		push_error("Narrative: cannot start dialogue '%s' from inside a dialogue transition" % dialogue_id)
		return false
	if _phase != Phase.IDLE:
		push_error("Narrative: cannot start dialogue '%s' — '%s' is already running (call end_dialogue() first)" % [dialogue_id, _dialogue.id])
		return false
	var dialogue := _database.get_dialogue(dialogue_id)
	if dialogue == null:
		push_error("Narrative: unknown dialogue id '%s'" % dialogue_id)
		return false
	var node_id := start_node_id if start_node_id != "" else dialogue.start_node_id
	if node_id == "":
		push_error("Narrative: dialogue '%s' has no start_node_id" % dialogue_id)
		return false
	if not dialogue.has_node_id(node_id):
		push_error("Narrative: dialogue '%s' has no node '%s'" % [dialogue_id, node_id])
		return false
	_busy = true
	_dialogue = dialogue
	_state.current_dialogue = {"dialogue_id": dialogue_id, "node_id": node_id, "phase": "at_line"}
	dialogue_started.emit(dialogue_id)
	_enter_node(node_id)
	_drain()
	_busy = false
	return true


## Moves past the current line. Illegal while choices are presented (unless
## every visible choice is disabled — an authoring-error escape hatch).
func advance() -> bool:
	if _busy:
		return _queue({"type": "advance"})
	if _phase == Phase.IDLE:
		push_warning("Narrative: advance() called with no active dialogue")
		return false
	if _phase == Phase.AT_CHOICES and not _all_visible_disabled():
		push_warning("Narrative: advance() called while choices are presented — use select_choice()")
		return false
	_busy = true
	_do_advance()
	_drain()
	_busy = false
	return true


## Selects a presented choice by id.
func select_choice(choice_id: String) -> bool:
	if _busy:
		return _queue({"type": "choice", "id": choice_id})
	if _phase != Phase.AT_CHOICES:
		push_warning("Narrative: select_choice('%s') called but no choices are presented" % choice_id)
		return false
	_busy = true
	var ok := _do_select(choice_id)
	_drain()
	_busy = false
	return ok


## Ends the running dialogue immediately.
func end_dialogue() -> bool:
	if _busy:
		return _queue({"type": "end"})
	if _phase == Phase.IDLE:
		push_warning("Narrative: end_dialogue() called with no active dialogue")
		return false
	_busy = true
	_finish()
	_drain()
	_busy = false
	return true


## The currently presented node resource (read-only by contract), or null.
func get_current_node() -> NarrativeDialogueNode:
	return _node


## Payload identical to the choices_presented signal argument.
func get_available_choices() -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for entry in _visible:
		var choice: NarrativeChoice = entry.choice
		payload.append({
			"id": choice.id,
			"text": _resolve_choice_text(choice),
			"enabled": bool(entry.enabled),
		})
	return payload


func is_dialogue_running() -> bool:
	return _phase != Phase.IDLE


func is_waiting_for_choice() -> bool:
	return _phase == Phase.AT_CHOICES


func get_current_dialogue_id() -> String:
	return _dialogue.id if _dialogue != null else ""


## Resolved (localized) text of the currently presented line, "" when idle.
## Lets late-instanced UIs pull the current state once on attach.
func get_current_line_text() -> String:
	if _node == null or _dialogue == null:
		return ""
	return _resolve_node_text(_node)


## True when no transition is processing (safe to save).
func is_settled() -> bool:
	return not _busy


func get_character(character_id: String) -> NarrativeCharacter:
	return _database.get_character(character_id)


## Localized display name; falls back to the raw id for unknown characters
## (the validator reports those at authoring time).
func get_character_display_name(character_id: String) -> String:
	if character_id == "":
		return ""
	var character := _database.get_character(character_id)
	if character == null:
		return character_id
	var inline := character.display_name if character.display_name != "" else character.id
	return _localization.resolve(
		character.display_name_key,
		NarrativeLocalizationManager.character_name_key(character_id),
		inline,
	)


## Called by the set_expression DSL builtin / sequencer command.
func notify_expression(character_id: String, expression: String) -> void:
	expression_changed.emit(character_id, expression)


## Re-presents the dialogue position stored in NarrativeState.current_dialogue
## (set by the SaveManager). PRESENTATION ONLY: node actions and sequencer
## commands are not re-run (their effects are already in the restored state),
## and the node is not re-added to seen/history. Choice conditions are
## re-evaluated against the restored variables. Returns true when resumed;
## a missing dialogue/node drops the saved position with a warning.
func try_resume() -> bool:
	if _phase != Phase.IDLE:
		push_error("Narrative: try_resume() called while a dialogue is running")
		return false
	var current: Dictionary = _state.current_dialogue
	if current.is_empty():
		return false
	var dialogue_id := str(current.get("dialogue_id", ""))
	var node_id := str(current.get("node_id", ""))
	var dialogue := _database.get_dialogue(dialogue_id)
	if dialogue == null or not dialogue.has_node_id(node_id):
		push_warning("Narrative: saved dialogue position '%s/%s' no longer exists in the database — dropping it" % [dialogue_id, node_id])
		_state.current_dialogue = {}
		return false
	_busy = true
	_dialogue = dialogue
	_node = dialogue.get_node_by_id(node_id)
	_visible = _build_visible_choices(_node)
	if _visible.is_empty():
		_phase = Phase.AT_LINE
		_state.current_dialogue.phase = "at_line"
	else:
		_phase = Phase.AT_CHOICES
		_state.current_dialogue.phase = "at_choices"
	dialogue_resumed.emit(dialogue_id, node_id)
	line_presented.emit(_node.speaker_id, _resolve_node_text(_node))
	if _phase == Phase.AT_CHOICES:
		choices_presented.emit(get_available_choices())
	_drain()
	_busy = false
	return true


# --- internals ---


func _do_advance() -> void:
	if _sequencer != null:
		_sequencer.cancel_current()
	if _node == null or _node.next_node_id == "":
		_finish()
	else:
		_enter_node(_node.next_node_id)


func _do_select(choice_id: String) -> bool:
	var entry := _find_visible_choice(choice_id)
	if entry.is_empty():
		push_error("Narrative: unknown or hidden choice id '%s' in dialogue '%s'" % [choice_id, get_current_dialogue_id()])
		return false
	if not entry.enabled:
		push_error("Narrative: choice '%s' is disabled (condition not met)" % choice_id)
		return false
	if _sequencer != null:
		_sequencer.cancel_current()
	var choice: NarrativeChoice = entry.choice
	choice_selected.emit(choice_id)
	if choice.actions.strip_edges() != "":
		_evaluator.run_actions(choice.actions, _label("choice '%s' actions" % choice_id))
	if choice.target_node_id == "":
		_finish()
	else:
		_enter_node(choice.target_node_id)
	return true


func _enter_node(start_node_id: String) -> void:
	var node_id := start_node_id
	var hops := 0
	while true:
		var node := _dialogue.get_node_by_id(node_id)
		if node == null:
			push_error("Narrative: dialogue '%s' links to missing node '%s' — ending dialogue" % [_dialogue.id, node_id])
			_finish()
			return
		hops += 1
		if hops > _max_hops:
			push_error("Narrative: dialogue '%s' exceeded max_node_hops (%d) at node '%s' — possible condition-skip loop; ending dialogue" % [_dialogue.id, _max_hops, node_id])
			_finish()
			return
		_node = node
		_state.current_dialogue = {"dialogue_id": _dialogue.id, "node_id": node_id, "phase": "at_line"}
		node_entered.emit(node_id)

		# Condition gate BEFORE marking the node as seen, so a node may use
		# `not has_seen(...)` on itself for first-time variations.
		if node.conditions.strip_edges() != "" and not _evaluator.eval_condition(node.conditions, _label("node '%s' conditions" % node_id)):
			if node.next_node_id == "":
				_finish()
				return
			node_id = node.next_node_id
			continue

		_state.mark_seen(_dialogue.id, node_id)
		_state.append_history(_dialogue.id, node_id)

		if node.actions.strip_edges() != "":
			_evaluator.run_actions(node.actions, _label("node '%s' actions" % node_id))

		_visible = _build_visible_choices(node)
		if _visible.is_empty():
			if not node.choices.is_empty():
				push_warning("Narrative: node '%s' — all choices hidden by conditions; presenting as a plain line" % node_id)
			_phase = Phase.AT_LINE
			_state.current_dialogue.phase = "at_line"
		else:
			_phase = Phase.AT_CHOICES
			_state.current_dialogue.phase = "at_choices"
			if _all_visible_disabled():
				push_warning("Narrative: node '%s' — all visible choices are disabled; advance() is allowed as an escape" % node_id)

		line_presented.emit(node.speaker_id, _resolve_node_text(node))
		if _phase == Phase.AT_CHOICES:
			choices_presented.emit(get_available_choices())
		if _sequencer != null and node.sequencer_commands.strip_edges() != "":
			_sequencer.start_run(node.sequencer_commands, _label("node '%s' sequence" % node_id))
		return


func _finish() -> void:
	var ended_id := get_current_dialogue_id()
	if _sequencer != null:
		_sequencer.cancel_current()
	_phase = Phase.IDLE
	_node = null
	_dialogue = null
	_visible = []
	_state.current_dialogue = {}
	dialogue_ended.emit(ended_id)


func _build_visible_choices(node: NarrativeDialogueNode) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for choice in node.choices:
		if choice == null:
			continue
		var enabled := true
		if choice.condition.strip_edges() != "":
			enabled = _evaluator.eval_condition(choice.condition, _label("choice '%s' condition" % choice.id))
		if enabled:
			visible.append({"choice": choice, "enabled": true})
		elif choice.show_disabled:
			visible.append({"choice": choice, "enabled": false})
	return visible


func _find_visible_choice(choice_id: String) -> Dictionary:
	for entry in _visible:
		if entry.choice.id == choice_id:
			return entry
	return {}


func _all_visible_disabled() -> bool:
	if _visible.is_empty():
		return false
	for entry in _visible:
		if entry.enabled:
			return false
	return true


func _queue(item: Dictionary) -> bool:
	if not _pending.is_empty():
		push_warning("Narrative: input queue full — %s dropped" % str(item.type))
		return false
	_pending.append(item)
	return true


func _drain() -> void:
	while not _pending.is_empty():
		var item: Dictionary = _pending.pop_front()
		match str(item.type):
			"advance":
				if _phase == Phase.AT_LINE or (_phase == Phase.AT_CHOICES and _all_visible_disabled()):
					_do_advance()
				elif _phase == Phase.AT_CHOICES:
					push_warning("Narrative: queued advance ignored — choices are presented")
			"choice":
				if _phase == Phase.AT_CHOICES:
					_do_select(str(item.id))
				else:
					push_warning("Narrative: queued select_choice('%s') ignored — no choices presented" % str(item.id))
			"end":
				if _phase != Phase.IDLE:
					_finish()


func _resolve_node_text(node: NarrativeDialogueNode) -> String:
	return TextMarkup.substitute_variables(_localization.resolve(
		node.localized_text_key,
		NarrativeLocalizationManager.node_text_key(_dialogue.id, node.id),
		node.text,
	), _state)


func _resolve_choice_text(choice: NarrativeChoice) -> String:
	return TextMarkup.substitute_variables(_localization.resolve(
		choice.localized_text_key,
		NarrativeLocalizationManager.choice_text_key(_dialogue.id, _node.id, choice.id),
		choice.text,
	), _state)


## Called by the context when the language changes: re-presents the current
## line/choices in the new language; UIs just redraw.
func on_language_changed(_locale: String) -> void:
	if _phase == Phase.IDLE or _node == null:
		return
	line_presented.emit(_node.speaker_id, _resolve_node_text(_node))
	if _phase == Phase.AT_CHOICES:
		choices_presented.emit(get_available_choices())


func _label(detail: String) -> String:
	return "dialogue '%s' %s" % [get_current_dialogue_id(), detail]
