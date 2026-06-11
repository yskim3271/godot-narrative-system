@tool
extends VBoxContainer
## Preview tab: plays a dialogue inside the editor against a sandboxed
## NarrativeContext. Every run gets a FRESH context (fresh state) built from
## the loaded database — resources are never mutated (runtime contract), so
## previewing cannot dirty authoring data.
##
## Differences from the game runtime, by design:
##  - the sequencer is detached: 🎬 sequence lines are logged, not executed
##    (no scene, no actors, no timers in the editor)
##  - alerts/quest updates/expression changes are logged into the transcript
##
## Headless-testable: no EditorInterface usage at all.

const LOG_DIM := Color(1, 1, 1, 0.5)

var _db: NarrativeDatabase
var _ctx: NarrativeContext

var _dialogue_picker: OptionButton
var _language_picker: OptionButton
var _start_button: Button
var _stop_button: Button
var _status: Label
var _log: RichTextLabel
var _next_button: Button
var _choices_box: VBoxContainer
var _state_tree: Tree


func _init() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var dialogue_label := Label.new()
	dialogue_label.text = "Dialogue:"
	toolbar.add_child(dialogue_label)

	_dialogue_picker = OptionButton.new()
	_dialogue_picker.custom_minimum_size = Vector2(160, 0)
	toolbar.add_child(_dialogue_picker)

	var language_label := Label.new()
	language_label.text = "Language:"
	toolbar.add_child(language_label)

	_language_picker = OptionButton.new()
	_language_picker.custom_minimum_size = Vector2(70, 0)
	_language_picker.item_selected.connect(func(_index: int) -> void:
		if _ctx != null:
			_ctx.localization.set_language(_selected_language()))
	toolbar.add_child(_language_picker)

	_start_button = Button.new()
	_start_button.text = "▶ Start"
	_start_button.tooltip_text = "Start (or restart) the selected dialogue with a fresh state"
	_start_button.pressed.connect(func() -> void: start_preview())
	toolbar.add_child(_start_button)

	_stop_button = Button.new()
	_stop_button.text = "■ Stop"
	_stop_button.pressed.connect(stop_preview)
	toolbar.add_child(_stop_button)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	split.add_child(left)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 80)
	left.add_child(_log)

	_choices_box = VBoxContainer.new()
	left.add_child(_choices_box)

	_next_button = Button.new()
	_next_button.text = "Next ▸"
	_next_button.disabled = true
	_next_button.pressed.connect(func() -> void: advance())
	left.add_child(_next_button)

	_state_tree = Tree.new()
	_state_tree.columns = 2
	_state_tree.set_column_title(0, "State")
	_state_tree.set_column_title(1, "Value")
	_state_tree.column_titles_visible = true
	_state_tree.hide_root = true
	_state_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_tree.size_flags_stretch_ratio = 1.0
	split.add_child(_state_tree)


## Refreshes the pickers; stops any running preview (the old context belongs
## to the old database).
func set_database(db: NarrativeDatabase) -> void:
	stop_preview()
	_db = db
	_refresh_pickers()


# --- preview lifecycle (public for tests and toolbar) ---


## Starts (or restarts) a dialogue on a fresh sandbox context.
func start_preview(dialogue_id := "") -> bool:
	stop_preview()
	if _db == null:
		_set_status("load a database first", true)
		return false
	var id := dialogue_id if dialogue_id != "" else _selected_dialogue()
	if id == "":
		_set_status("no dialogue selected", true)
		return false
	_select_dialogue_item(id)

	_ctx = NarrativeContext.create(_db)
	_ctx.runner.set_sequencer(null)  # editor preview never executes stage commands
	_ctx.localization.set_language(_selected_language())
	_ctx.runner.line_presented.connect(_on_line_presented)
	_ctx.runner.choices_presented.connect(_on_choices_presented)
	_ctx.runner.choice_selected.connect(_on_choice_selected)
	_ctx.runner.dialogue_ended.connect(_on_dialogue_ended)
	_ctx.runner.expression_changed.connect(_on_expression_changed)
	_ctx.quests.quest_updated.connect(_on_quest_updated)
	_ctx.state.variable_changed.connect(_on_variable_changed)
	_ctx.alert_requested.connect(_on_alert)

	_log.clear()
	_append("[i]— preview '%s' (%s) —[/i]" % [id, _selected_language()], LOG_DIM)
	if not _ctx.runner.start_dialogue(id):
		_set_status("cannot start dialogue '%s'" % id, true)
		stop_preview()
		return false
	_set_status("running '%s'" % id)
	_refresh_state_tree()
	_update_controls()
	return true


## Ends the run and drops the sandbox context (the transcript stays visible).
func stop_preview() -> void:
	if _ctx == null:
		return
	if _ctx.runner.is_dialogue_running():
		_ctx.runner.end_dialogue()
	_ctx = null  # frees the whole sandbox graph and its signal connections
	_clear_choices()
	_update_controls()
	_set_status("stopped")


func advance() -> bool:
	if not is_running():
		return false
	return _ctx.runner.advance()


func select_choice(choice_id: String) -> bool:
	if not is_running():
		return false
	return _ctx.runner.select_choice(choice_id)


func is_running() -> bool:
	return _ctx != null and _ctx.runner.is_dialogue_running()


## Switches the preview language (picker + running context; the runner
## re-presents the current line/choices through the normal runtime path).
func set_preview_language(locale: String) -> void:
	for i in _language_picker.item_count:
		if _language_picker.get_item_text(i) == locale:
			_language_picker.select(i)
			break
	if _ctx != null:
		_ctx.localization.set_language(locale)


## The sandbox context of the current run (tests/tooling), null when stopped.
func context() -> NarrativeContext:
	return _ctx


## Plain-text transcript (tests).
func log_text() -> String:
	return _log.get_parsed_text()


## The currently presented choice buttons (tests).
func choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child in _choices_box.get_children():
		if child is Button:
			buttons.append(child)
	return buttons


# --- signal handlers (sandbox -> transcript) ---


func _on_line_presented(speaker_id: String, text: String) -> void:
	var node := _ctx.runner.get_current_node()
	var node_tag := "[%s] " % node.id if node != null else ""
	var line := text
	if speaker_id != "":
		line = "[b]%s:[/b] %s" % [_escape(_ctx.runner.get_character_display_name(speaker_id)), text]
	_append_dim_prefix(node_tag, line)
	if node != null and node.sequencer_commands.strip_edges() != "":
		var commands := " | ".join(node.sequencer_commands.split("\n", false))
		_append("🎬 sequence (not executed in preview): %s" % _escape(commands), LOG_DIM)
	_update_controls()


func _on_choices_presented(choices: Array) -> void:
	_clear_choices()
	for entry: Dictionary in choices:
		var button := Button.new()
		button.text = str(entry.text)
		button.disabled = not bool(entry.enabled)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta("choice_id", str(entry.id))
		button.pressed.connect(select_choice.bind(str(entry.id)))
		_choices_box.add_child(button)
	_update_controls()


func _on_choice_selected(choice_id: String) -> void:
	_append("▷ %s" % _escape(choice_id), LOG_DIM)
	_clear_choices()


func _on_dialogue_ended(dialogue_id: String) -> void:
	_append("[i]— dialogue '%s' ended —[/i]" % _escape(dialogue_id), LOG_DIM)
	_clear_choices()
	_update_controls()
	_set_status("finished '%s'" % dialogue_id)


func _on_quest_updated(quest_id: String) -> void:
	if _ctx == null:
		return
	_append("📜 quest '%s' → %s" % [_escape(quest_id), _ctx.quests.get_quest_state(quest_id)], LOG_DIM)
	_refresh_state_tree()


func _on_alert(text: String) -> void:
	_append("🔔 %s" % _escape(text), LOG_DIM)


func _on_expression_changed(character_id: String, expression: String) -> void:
	_append("🎭 %s: %s" % [_escape(character_id), _escape(expression)], LOG_DIM)


func _on_variable_changed(_variable_id: String, _value: Variant) -> void:
	_refresh_state_tree()


# --- UI internals ---


func _refresh_pickers() -> void:
	_dialogue_picker.clear()
	_language_picker.clear()
	if _db == null:
		return
	var ids: Array[String] = []
	for dialogue in _db.dialogues:
		if dialogue != null and dialogue.id != "":
			ids.append(dialogue.id)
	ids.sort()
	for id in ids:
		_dialogue_picker.add_item(id)

	var settings := _db.get_settings()
	var locales := {settings.default_language: true, settings.fallback_language: true}
	for table in _db.localization_tables:
		if table != null:
			for locale in table.collect_locales():
				locales[locale] = true
	var sorted := PackedStringArray()
	for locale: String in locales:
		if locale != "":
			sorted.append(locale)
	sorted.sort()
	for locale in sorted:
		_language_picker.add_item(locale)
		if locale == settings.default_language:
			_language_picker.select(_language_picker.item_count - 1)


func _selected_dialogue() -> String:
	if _dialogue_picker.selected < 0:
		return ""
	return _dialogue_picker.get_item_text(_dialogue_picker.selected)


func _select_dialogue_item(dialogue_id: String) -> void:
	for i in _dialogue_picker.item_count:
		if _dialogue_picker.get_item_text(i) == dialogue_id:
			_dialogue_picker.select(i)
			return


func _selected_language() -> String:
	if _language_picker.selected < 0:
		return _db.get_settings().default_language if _db != null else "en"
	return _language_picker.get_item_text(_language_picker.selected)


func _refresh_state_tree() -> void:
	_state_tree.clear()
	var root := _state_tree.create_item()
	if _ctx == null:
		return
	var variables := _state_tree.create_item(root)
	variables.set_text(0, "Variables")
	variables.set_selectable(0, false)
	variables.set_selectable(1, false)
	var values := _ctx.state.variable_values()
	var ids := values.keys()
	ids.sort()
	for variable_id in ids:
		var row := _state_tree.create_item(variables)
		row.set_text(0, str(variable_id))
		row.set_text(1, str(values[variable_id]))

	var quests := _state_tree.create_item(root)
	quests.set_text(0, "Quests")
	quests.set_selectable(0, false)
	quests.set_selectable(1, false)
	for state: String in ["active", "completed", "failed"]:
		for quest_id in _ctx.quests.get_quests_in_state(state):
			var row := _state_tree.create_item(quests)
			row.set_text(0, str(quest_id))
			var info: String = state
			if state == "active":
				var parts := PackedStringArray()
				for progress in _ctx.quests.get_objectives_progress(quest_id):
					parts.append("%s %d/%d" % [progress.id, progress.count, progress.target])
				if not parts.is_empty():
					info += " (%s)" % ", ".join(parts)
			row.set_text(1, info)


func _update_controls() -> void:
	var running := is_running()
	_stop_button.disabled = not running
	var can_advance := running and not _ctx.runner.is_waiting_for_choice()
	if running and _ctx.runner.is_waiting_for_choice():
		# authoring-error escape hatch: all visible choices disabled
		var any_enabled := false
		for entry in _ctx.runner.get_available_choices():
			if bool(entry.enabled):
				any_enabled = true
				break
		can_advance = not any_enabled
	_next_button.disabled = not can_advance


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()


func _append(bbcode: String, color := Color.WHITE) -> void:
	if color == Color.WHITE:
		_log.append_text(bbcode + "\n")
		return
	_log.push_color(color)
	_log.append_text(bbcode + "\n")
	_log.pop()


func _append_dim_prefix(prefix: String, bbcode: String) -> void:
	if prefix != "":
		_log.push_color(LOG_DIM)
		_log.append_text(_escape(prefix))
		_log.pop()
	_log.append_text(bbcode + "\n")


## Escapes BBCode in untrusted fragments (ids, names). Dialogue text itself is
## NOT escaped — [color=…] markup is meant to render in the preview.
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.55, 0.55) if is_error else Color(1, 1, 1, 0.7)
