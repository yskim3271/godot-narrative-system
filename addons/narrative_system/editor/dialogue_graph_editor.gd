@tool
extends Control
## Main-screen dialogue graph editor (M2).
##
## A thin GraphEdit shell over dialogue_graph_model.gd: all graph mutations
## go through the model (headless-tested); this class only visualizes and
## forwards user gestures. It is instantiable WITHOUT the editor (tests):
## every EditorInterface use is guarded by Engine.is_editor_hint().
##
## Port contract (per GraphNode):
##   input  port 0          = incoming links
##   output port 0          = next_node_id        (slot 0, header row)
##   output port 1..N       = choices[port - 1]   (slots 2.., one per choice)
## Slot 1 is the portless text-editor row.
##
## Inline editing (undoable): the node id and speaker_id (header row, slot 0 —
## renaming the id retargets every link to it), text (slot 1) and each choice's
## text + target id (slots 2+) are edited in place. The title mirrors the id
## read-only (▶ marks the start node).
## Remaining fields (conditions/actions/sequencer, choice conditions) are
## edited in the Inspector — selecting a node opens its NarrativeDialogueNode
## there; those show as ❓⚡🎬 badges and refresh after Refresh / re-opening
## the tab. All edits (inline + structural add/delete/link/move/set-start/
## rename) are undoable through the injected EditorUndoRedoManager (see
## set_undo_redo and docs/graph_editor.md).
##
## Markup helpers inside the text/choice-text fields:
##   Ctrl+Shift+V — insert [var=…] (selection becomes the variable name)
##   Ctrl+Shift+C — wrap the selection in [color=…][/color]
## Ctrl+Shift+N (canvas) / the "1.2.3" toolbar button toggles "1. " numbering
## on the selected node's choice texts.

const GraphModel := preload("dialogue_graph_model.gd")
const SETTING_DATABASE_PATH := "narrative_system/database_path"

const COLOR_IN := Color(0.78, 0.78, 0.78)
const COLOR_NEXT := Color(0.55, 0.78, 1.0)
const COLOR_CHOICE := Color(1.0, 0.84, 0.4)
const MENU_ADD_NODE := 0
const MARKUP_COLOR_DEFAULT := "yellow"
const MARKUP_TOOLTIP := "Ctrl+Shift+V inserts [var=…], Ctrl+Shift+C wraps [color=…]"

var _db: NarrativeDatabase
var _dialogue: NarrativeDialogue
var _dirty := false
var _gname_to_id := {}
var _id_to_gname := {}
var _next_gname := 0
var _popup_graph_pos := Vector2.ZERO
## EditorUndoRedoManager injected by plugin.gd (null when headless/tests:
## actions then execute directly with identical effects, no history).
var _undo_redo: Object = null
var _move_snapshot := {}

var _graph: GraphEdit
var _picker: OptionButton
var _status: Label
var _context_menu: PopupMenu
var _new_dialog: ConfirmationDialog
var _new_dialog_edit: LineEdit


func _init() -> void:
	name = "NarrativeGraphEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The editor main screen is a Container (VBoxContainer): it sizes children
	# by size flags and IGNORES anchors. Without EXPAND_FILL the control would
	# collapse to its minimum height there, leaving the GraphEdit zero-height
	# and every node invisible. The anchors above still cover non-container
	# parents (tests, standalone embedding).
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


func _ready() -> void:
	if Engine.is_editor_hint():
		reload_database()


## Accepts an EditorUndoRedoManager (or any object with the same
## create_action/add_do_method/add_undo_method/commit_action surface).
func set_undo_redo(manager: Object) -> void:
	_undo_redo = manager


# --- public API (used by plugin.gd and tests) ---


## Loads the database from the project setting (editor path).
func reload_database() -> void:
	var path := str(ProjectSettings.get_setting(SETTING_DATABASE_PATH, ""))
	if path == "" or not ResourceLoader.exists(path):
		_set_status("project setting %s is not set — use the bottom Narrative panel to pick a database" % SETTING_DATABASE_PATH, true)
		return
	var db := load(path) as NarrativeDatabase
	if db == null:
		_set_status("not a NarrativeDatabase: %s" % path, true)
		return
	set_database(db)


## Direct injection (tests / panel integration).
func set_database(db: NarrativeDatabase) -> void:
	_db = db
	_refresh_picker()
	if _db != null and not _db.dialogues.is_empty():
		var first: String = _picker.get_item_metadata(0) if _picker.item_count > 0 else ""
		open_dialogue(first)


## Rebuilds the canvas for one dialogue. Returns false for unknown ids.
func open_dialogue(dialogue_id: String) -> bool:
	if _db == null:
		return false
	var dialogue := _db.get_dialogue(dialogue_id)
	if dialogue == null:
		_set_status("unknown dialogue '%s'" % dialogue_id, true)
		return false
	_dialogue = dialogue
	GraphModel.auto_layout(dialogue)
	_select_picker_item(dialogue_id)
	_rebuild()
	_set_status("opened '%s' (%d nodes)" % [dialogue_id, dialogue.nodes.size()])
	return true


## Re-reads the current dialogue (e.g. after Inspector edits).
func refresh_view() -> void:
	if _dialogue != null:
		open_dialogue(_dialogue.id)


## Opens a dialogue and (when node_id is given) selects + centers that node.
## Used by the bottom panel to jump from validation/localization rows to the
## graph. Returns false when the dialogue (or the requested node) is unknown.
func focus_node(dialogue_id: String, node_id := "") -> bool:
	if _db == null:
		return false
	if _dialogue == null or _dialogue.id != dialogue_id:
		if not open_dialogue(dialogue_id):
			return false
	if node_id == "":
		return true
	var gname: String = _id_to_gname.get(node_id, "")
	if gname == "" or not _graph.has_node(NodePath(gname)):
		_set_status("node '%s' is not in dialogue '%s'" % [node_id, dialogue_id], true)
		return false
	var gnode := _graph.get_node(NodePath(gname)) as GraphNode
	for child in _graph.get_children():
		if child is GraphNode:
			child.selected = child == gnode
	# Center the view on the node (scroll_offset is in zoomed pixels).
	_graph.scroll_offset = gnode.position_offset * _graph.zoom \
		- (_graph.size - gnode.size * _graph.zoom) * 0.5
	_set_status("focused '%s' / '%s'" % [dialogue_id, node_id])
	return true


func current_dialogue() -> NarrativeDialogue:
	return _dialogue


func get_graph_edit() -> GraphEdit:
	return _graph


func graph_name_for(node_id: String) -> StringName:
	return StringName(_id_to_gname.get(node_id, ""))


## Adds a node at a canvas position and shows it (undoable).
func add_node_at(position: Vector2) -> NarrativeDialogueNode:
	if _dialogue == null:
		_set_status("open a dialogue first", true)
		return null
	var node := NarrativeDialogueNode.new()
	node.id = GraphModel.generate_node_id(_dialogue)
	GraphModel.set_position(node, position)
	_run_action("Add dialogue node",
		"_ur_add", {"node": node},
		"_ur_unadd", {"node_id": node.id, "prev_start": _dialogue.start_node_id})
	_set_status("added node '%s'" % node.id)
	return node


func add_node_at_view_center() -> NarrativeDialogueNode:
	var center := (_graph.scroll_offset + _graph.size * 0.5) / _graph.zoom
	return add_node_at(center)


func delete_selection() -> void:
	_on_delete_nodes_request(_selected_graph_names())


func set_selection_as_start() -> void:
	var selection := _selected_graph_names()
	if selection.size() != 1:
		_set_status("select exactly one node to mark as start", true)
		return
	var node_id: String = _gname_to_id.get(str(selection[0]), "")
	if node_id == "" or not _dialogue.has_node_id(node_id) or node_id == _dialogue.start_node_id:
		return
	_run_action("Set start node",
		"_ur_start", {"node_id": node_id},
		"_ur_start", {"node_id": _dialogue.start_node_id})
	_set_status("start node: '%s'" % node_id)


## Persists node positions and writes the database resource to disk.
func save_database() -> void:
	if _db == null:
		return
	_persist_positions()
	if _db.resource_path == "" or _db.resource_path.contains("::"):
		_set_status("database has no file path — save it from the Inspector first", true)
		return
	var err := ResourceSaver.save(_db)
	if err != OK:
		_set_status("save failed: %s" % error_string(err), true)
		return
	_dirty = false
	_set_status("saved %s" % _db.resource_path.get_file())


func validate_database() -> void:
	if _db == null:
		return
	var issues := NarrativeValidator.new().validate(_db)
	var errors := NarrativeValidator.count_severity(issues, "error")
	var warnings := NarrativeValidator.count_severity(issues, "warning")
	_set_status("validation: %d error(s), %d warning(s) — details in the bottom Narrative panel" % [errors, warnings], errors > 0)


# --- UI construction ---


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var toolbar := HBoxContainer.new()
	vbox.add_child(toolbar)

	var picker_label := Label.new()
	picker_label.text = "Dialogue:"
	toolbar.add_child(picker_label)

	_picker = OptionButton.new()
	_picker.custom_minimum_size = Vector2(180, 0)
	_picker.item_selected.connect(func(index: int) -> void:
		open_dialogue(str(_picker.get_item_metadata(index))))
	toolbar.add_child(_picker)

	_toolbar_button(toolbar, "New Dialogue", func() -> void: _show_new_dialogue_dialog())
	toolbar.add_child(VSeparator.new())
	_toolbar_button(toolbar, "Add Node", func() -> void: add_node_at_view_center())
	_toolbar_button(toolbar, "Set Start", set_selection_as_start)
	_toolbar_button(toolbar, "Delete", delete_selection)
	_toolbar_button(toolbar, "1.2.3", auto_number_selected_choices,
		"Toggle \"1. \" numbering on the selected node's choice texts (Ctrl+Shift+N)")
	toolbar.add_child(VSeparator.new())
	_toolbar_button(toolbar, "Save", save_database)
	_toolbar_button(toolbar, "Validate", validate_database)
	_toolbar_button(toolbar, "Refresh", refresh_view)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status)

	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph.popup_request.connect(_on_popup_request)
	_graph.node_selected.connect(_on_node_selected)
	_graph.begin_node_move.connect(_on_begin_node_move)
	_graph.end_node_move.connect(_on_end_node_move)
	_graph.gui_input.connect(_on_graph_gui_input)
	vbox.add_child(_graph)

	_context_menu = PopupMenu.new()
	_context_menu.add_item("Add Node Here", MENU_ADD_NODE)
	_context_menu.id_pressed.connect(func(id: int) -> void:
		if id == MENU_ADD_NODE:
			add_node_at(_popup_graph_pos))
	add_child(_context_menu)

	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "New Dialogue"
	_new_dialog_edit = LineEdit.new()
	_new_dialog_edit.placeholder_text = "dialogue id  [a-zA-Z0-9_.]"
	_new_dialog.add_child(_new_dialog_edit)
	_new_dialog.register_text_enter(_new_dialog_edit)
	_new_dialog.confirmed.connect(_on_new_dialogue_confirmed)
	add_child(_new_dialog)


func _toolbar_button(parent: Control, text: String, handler: Callable, tooltip := "") -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(handler)
	parent.add_child(button)


# --- canvas building ---


func _rebuild() -> void:
	_graph.clear_connections()
	for child in _graph.get_children():
		if child is GraphNode:
			_graph.remove_child(child)
			child.queue_free()
	_gname_to_id.clear()
	_id_to_gname.clear()
	if _dialogue == null:
		return
	for node in _dialogue.nodes:
		if node != null and node.id != "":
			_spawn_graph_node(node)
	_refresh_connections()
	_update_start_styling()


func _spawn_graph_node(node: NarrativeDialogueNode) -> GraphNode:
	var gnode := GraphNode.new()
	var gname := "gn_%d" % _next_gname
	_next_gname += 1
	gnode.name = gname
	_gname_to_id[gname] = node.id
	_id_to_gname[node.id] = gname
	# Title shows the id (read-only, ▶ for the start node — see _update_start_styling).
	gnode.title = node.id
	gnode.position_offset = GraphModel.get_position(node)

	# slot 0 — header: id (rename) + speaker editors + badges, in/out ports.
	# These live in the node BODY, not the titlebar: titlebar children fight the
	# node-drag/select gesture and never reliably grab keyboard focus.
	var header := HBoxContainer.new()
	var id_edit := LineEdit.new()
	id_edit.text = node.id
	id_edit.custom_minimum_size = Vector2(96, 0)
	id_edit.tooltip_text = "Node id — renaming retargets every link to it"
	header.add_child(id_edit)
	var speaker_edit := LineEdit.new()
	speaker_edit.text = node.speaker_id
	speaker_edit.placeholder_text = "(narrator)"
	speaker_edit.flat = true
	speaker_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_edit.custom_minimum_size = Vector2(110, 0)
	speaker_edit.tooltip_text = "Speaker id"
	header.add_child(speaker_edit)
	var badges := Label.new()
	badges.text = _badge_text(node)
	header.add_child(badges)
	gnode.add_child(header)
	gnode.set_slot(0, true, 0, COLOR_IN, true, 0, COLOR_NEXT)
	gnode.set_meta("id_edit", id_edit)
	gnode.set_meta("speaker_edit", speaker_edit)
	_wire_inline_edit(id_edit, _commit_rename.bind(id_edit, node.id))
	_wire_inline_edit(speaker_edit, _commit_field.bind(speaker_edit, node.id, "speaker"))

	# slot 1 — editable dialogue text, no ports.
	var text_edit := TextEdit.new()
	text_edit.text = node.text
	text_edit.placeholder_text = "dialogue text…"
	text_edit.custom_minimum_size = Vector2(240, 60)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.scroll_fit_content_height = true
	text_edit.tooltip_text = "Dialogue text — " + MARKUP_TOOLTIP
	gnode.add_child(text_edit)
	gnode.set_meta("text_edit", text_edit)
	# TextEdit is multiline: Enter inserts a newline, so commit on focus loss only.
	text_edit.focus_entered.connect(_capture_edit_before.bind(text_edit))
	text_edit.focus_exited.connect(_commit_field.bind(text_edit, node.id, "text"))
	_wire_markup_keys(text_edit)

	# slots 2.. — one row per choice: inline text + target id, one output port.
	for i in node.choices.size():
		var choice := node.choices[i]
		if choice == null:
			var null_row := Label.new()
			null_row.text = "(null choice)"
			null_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			gnode.add_child(null_row)
			gnode.set_slot(2 + i, false, 0, COLOR_IN, true, 0, COLOR_CHOICE)
			continue
		var row := HBoxContainer.new()
		var choice_text := LineEdit.new()
		choice_text.text = choice.text
		choice_text.placeholder_text = "choice text…"
		choice_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice_text.custom_minimum_size = Vector2(150, 0)
		choice_text.tooltip_text = "Choice '%s' text — %s" % [choice.id, MARKUP_TOOLTIP]
		row.add_child(choice_text)
		var choice_target := LineEdit.new()
		choice_target.text = choice.target_node_id
		choice_target.placeholder_text = "(end)"
		choice_target.flat = true
		choice_target.custom_minimum_size = Vector2(86, 0)
		choice_target.tooltip_text = "Choice '%s' target node id — empty ends the dialogue" % choice.id
		row.add_child(choice_target)
		gnode.add_child(row)
		gnode.set_slot(2 + i, false, 0, COLOR_IN, true, 0, COLOR_CHOICE)
		gnode.set_meta("choice_text_%d" % i, choice_text)
		gnode.set_meta("choice_target_%d" % i, choice_target)
		_wire_inline_edit(choice_text, _commit_choice_text.bind(choice_text, node.id, i))
		_wire_inline_edit(choice_target, _commit_choice_target.bind(choice_target, node.id, i))
		_wire_markup_keys(choice_text)

	_graph.add_child(gnode)
	return gnode


## Wires a single-line field: capture its value on focus, commit on focus loss,
## and treat Enter as "done" (release focus -> triggers the commit).
func _wire_inline_edit(edit: LineEdit, commit: Callable) -> void:
	edit.focus_entered.connect(_capture_edit_before.bind(edit))
	edit.focus_exited.connect(commit)
	edit.text_submitted.connect(func(_t: String) -> void: edit.release_focus())


func _capture_edit_before(control: Control) -> void:
	control.set_meta("edit_before", control.text)


## Commits an inline text/speaker edit as one undoable action (before -> after
## captured per focus session, so a whole edit is a single undo step).
func _commit_field(control: Control, node_id: String, field: String) -> void:
	var before := str(control.get_meta("edit_before", control.text))
	var after: String = control.text
	if after == before:
		return
	_run_action("Edit dialogue %s" % field,
		"_ur_set_field", {"node_id": node_id, "field": field, "value": after},
		"_ur_set_field", {"node_id": node_id, "field": field, "value": before})


## Commits a node rename (with link retargeting) as one undoable action.
## Invalid/duplicate ids are rejected and the field reverts.
func _commit_rename(edit: LineEdit, node_id: String) -> void:
	var before := str(edit.get_meta("edit_before", node_id))
	var after := edit.text.strip_edges()
	if after == before:
		edit.text = before  # normalize any stray whitespace
		return
	if not GraphModel.is_valid_id(after) or (_dialogue != null and _dialogue.has_node_id(after)):
		_set_status("cannot rename '%s' → '%s' (invalid id or already in use)" % [before, after], true)
		edit.text = before
		return
	_run_action("Rename dialogue node",
		"_ur_rename", {"from": before, "to": after},
		"_ur_rename", {"from": after, "to": before})
	_set_status("renamed '%s' → '%s'" % [before, after])


## Commits an inline choice-text edit as one undoable action.
func _commit_choice_text(control: Control, node_id: String, choice_index: int) -> void:
	var before := str(control.get_meta("edit_before", control.text))
	var after: String = control.text
	if after == before:
		return
	_run_action("Edit choice text",
		"_ur_choice_text", {"node_id": node_id, "index": choice_index, "value": after},
		"_ur_choice_text", {"node_id": node_id, "index": choice_index, "value": before})


## Commits an inline choice-target edit. Empty ends the dialogue; unknown node
## ids are rejected and the field reverts. Shares _ur_link with port drags, so
## the canvas connection and the field stay in sync on do AND undo.
func _commit_choice_target(edit: LineEdit, node_id: String, choice_index: int) -> void:
	var before := str(edit.get_meta("edit_before", edit.text))
	var after := edit.text.strip_edges()
	if after == before:
		edit.text = before  # normalize stray whitespace
		return
	if after != "" and (_dialogue == null or not _dialogue.has_node_id(after)):
		_set_status("unknown target node '%s' — choice target reverted" % after, true)
		edit.text = before
		return
	_run_action("Retarget choice",
		"_ur_link", {"from_id": node_id, "port": choice_index + 1, "to_id": after},
		"_ur_link", {"from_id": node_id, "port": choice_index + 1, "to_id": before})


# --- markup helpers (inline text fields) ---


## Inserts a [var=…] tag at the caret; a selection becomes the variable name.
## Public so tests (and future toolbar UI) can call it without key events.
func insert_var_markup(control: Control) -> void:
	var name := _selected_field_text(control)
	_replace_field_selection(control, "[var=%s]" % name, 1 if name == "" else 0)


## Wraps the selection in [color=…][/color] (empty selection: caret lands
## between the tags).
func wrap_color_markup(control: Control) -> void:
	var selection := _selected_field_text(control)
	var inserted := "[color=%s]%s[/color]" % [MARKUP_COLOR_DEFAULT, selection]
	_replace_field_selection(control, inserted, "[/color]".length() if selection == "" else 0)


func _wire_markup_keys(control: Control) -> void:
	control.gui_input.connect(_on_markup_key.bind(control))


func _on_markup_key(event: InputEvent, control: Control) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not (key.is_command_or_control_pressed() and key.shift_pressed) or key.alt_pressed:
		return
	match key.keycode:
		KEY_V:
			insert_var_markup(control)
		KEY_C:
			wrap_color_markup(control)
		_:
			return
	control.accept_event()


func _selected_field_text(control: Control) -> String:
	if control is TextEdit:
		return (control as TextEdit).get_selected_text()
	var edit := control as LineEdit
	if edit == null or not edit.has_selection():
		return ""
	return edit.text.substr(edit.get_selection_from_column(),
		edit.get_selection_to_column() - edit.get_selection_from_column())


## Replaces the selection (or inserts at the caret) and parks the caret
## `caret_back` characters before the end of the inserted text. `inserted`
## must be single-line (markup tags are).
func _replace_field_selection(control: Control, inserted: String, caret_back: int) -> void:
	if control is TextEdit:
		var text_edit := control as TextEdit
		if text_edit.has_selection():
			text_edit.delete_selection()
		text_edit.insert_text_at_caret(inserted)
		text_edit.set_caret_column(text_edit.get_caret_column() - caret_back)
	elif control is LineEdit:
		var edit := control as LineEdit
		if edit.has_selection():
			var from := edit.get_selection_from_column()
			edit.delete_text(from, edit.get_selection_to_column())
			edit.caret_column = from
		edit.insert_text_at_caret(inserted)
		edit.caret_column -= caret_back


# --- choice auto-numbering ---


## Toggles "1. ", "2. ", … prefixes on the selected node's choice texts
## ("1.2.3" toolbar button / Ctrl+Shift+N on the canvas). One undo step.
func auto_number_selected_choices() -> void:
	if _dialogue == null:
		return
	var selection := _selected_graph_names()
	if selection.size() != 1:
		_set_status("select exactly one node to number its choices", true)
		return
	var node_id: String = _gname_to_id.get(str(selection[0]), "")
	var node := _dialogue.get_node_by_id(node_id)
	if node == null:
		return
	var before := _choice_texts(node)
	if before.is_empty():
		_set_status("node '%s' has no choices to number" % node_id, true)
		return
	var after := GraphModel.toggle_choice_numbering(before)
	if after == before:
		return
	_run_action("Auto-number choices",
		"_ur_choice_texts", {"node_id": node_id, "texts": after},
		"_ur_choice_texts", {"node_id": node_id, "texts": before})
	_set_status("numbered %d choice(s) on '%s'" % [after.size(), node_id])


func _choice_texts(node: NarrativeDialogueNode) -> PackedStringArray:
	var texts := PackedStringArray()
	for choice in node.choices:
		texts.append(choice.text if choice != null else "")
	return texts


func _on_graph_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.is_command_or_control_pressed() and key.shift_pressed and not key.alt_pressed \
			and key.keycode == KEY_N:
		auto_number_selected_choices()
		_graph.accept_event()


func _refresh_connections() -> void:
	_graph.clear_connections()
	if _dialogue == null:
		return
	for connection in GraphModel.connections(_dialogue):
		var from_name: String = _id_to_gname.get(connection.from_id, "")
		var to_name: String = _id_to_gname.get(connection.to_id, "")
		if from_name != "" and to_name != "":
			_graph.connect_node(from_name, int(connection.port), to_name, 0)


func _update_start_styling() -> void:
	if _dialogue == null:
		return
	for child in _graph.get_children():
		if child is GraphNode:
			var node_id: String = _gname_to_id.get(str(child.name), "")
			child.title = ("▶ " + node_id) if node_id == _dialogue.start_node_id else node_id


## Badges that flag fields edited only via the Inspector (conditions/actions/
## sequencer). Refreshed on rebuild — i.e. after Refresh or re-opening the tab.
func _badge_text(node: NarrativeDialogueNode) -> String:
	var badges := ""
	if node.conditions.strip_edges() != "":
		badges += "❓"
	if node.actions.strip_edges() != "":
		badges += "⚡"
	if node.sequencer_commands.strip_edges() != "":
		badges += "🎬"
	return badges


# --- gesture handlers (also called directly by tests) ---


func _on_connection_request(from_name: StringName, from_port: int, to_name: StringName, to_port: int) -> void:
	if to_port != 0 or _dialogue == null:
		return
	var from_id: String = _gname_to_id.get(str(from_name), "")
	var to_id: String = _gname_to_id.get(str(to_name), "")
	if from_id == "" or to_id == "":
		return
	if from_port > 0 and from_port - 1 >= _dialogue.get_node_by_id(from_id).choices.size():
		return
	var previous := _link_target(from_id, from_port)
	if previous == to_id:
		return
	_run_action("Connect dialogue nodes",
		"_ur_link", {"from_id": from_id, "port": from_port, "to_id": to_id},
		"_ur_link", {"from_id": from_id, "port": from_port, "to_id": previous})


func _on_disconnection_request(from_name: StringName, from_port: int, _to_name: StringName, _to_port: int) -> void:
	if _dialogue == null:
		return
	var from_id: String = _gname_to_id.get(str(from_name), "")
	if from_id == "":
		return
	var previous := _link_target(from_id, from_port)
	if previous == "":
		return
	_run_action("Disconnect dialogue nodes",
		"_ur_link", {"from_id": from_id, "port": from_port, "to_id": ""},
		"_ur_link", {"from_id": from_id, "port": from_port, "to_id": previous})


func _on_delete_nodes_request(names: Array) -> void:
	if _dialogue == null or names.is_empty():
		return
	var ids: Array = []
	var captures: Array = []
	for name in names:
		var node_id: String = _gname_to_id.get(str(name), "")
		if node_id == "" or not _dialogue.has_node_id(node_id):
			continue
		ids.append(node_id)
		captures.append(_capture_node(node_id))
	if ids.is_empty():
		return
	_run_action("Delete dialogue node(s)",
		"_ur_delete", {"ids": ids},
		"_ur_undelete", {"captures": captures})
	_set_status("deleted %d node(s)" % ids.size())


func _on_popup_request(at_position: Vector2) -> void:
	_popup_graph_pos = (at_position + _graph.scroll_offset) / _graph.zoom
	_context_menu.position = Vector2i(_graph.get_screen_position() + at_position)
	_context_menu.popup()


func _on_node_selected(node: Node) -> void:
	if not Engine.is_editor_hint() or _dialogue == null:
		return
	var node_id: String = _gname_to_id.get(str(node.name), "")
	var resource := _dialogue.get_node_by_id(node_id)
	if resource != null:
		EditorInterface.edit_resource(resource)


func _on_begin_node_move() -> void:
	_move_snapshot = _current_positions()


func _on_end_node_move() -> void:
	var after := _current_positions()
	var before := {}
	var changed := {}
	for node_id in after:
		var old: Vector2 = _move_snapshot.get(node_id, after[node_id])
		if old != after[node_id]:
			before[node_id] = old
			changed[node_id] = after[node_id]
	_move_snapshot = {}
	if changed.is_empty():
		return
	_run_action("Move dialogue node(s)",
		"_ur_positions", {"map": changed},
		"_ur_positions", {"map": before})


# --- undoable operations (single-payload methods for EditorUndoRedoManager) ---


## Runs do_method(do_payload) through the undo manager when present,
## or directly when headless. Both paths have identical effects.
func _run_action(action_name: String, do_method: StringName, do_payload: Dictionary, undo_method: StringName, undo_payload: Dictionary) -> void:
	if _undo_redo == null:
		call(do_method, do_payload)
		return
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(self, do_method, do_payload)
	_undo_redo.add_undo_method(self, undo_method, undo_payload)
	_undo_redo.commit_action()


func _ur_add(payload: Dictionary) -> void:
	var node: NarrativeDialogueNode = payload.node
	_dialogue.nodes.append(node)
	if _dialogue.start_node_id == "" and _dialogue.nodes.size() == 1:
		_dialogue.start_node_id = node.id
	_rebuild()
	_mark_dirty()


func _ur_unadd(payload: Dictionary) -> void:
	GraphModel.delete_node(_dialogue, str(payload.node_id))
	_dialogue.start_node_id = str(payload.prev_start)
	_rebuild()
	_mark_dirty()


func _ur_delete(payload: Dictionary) -> void:
	for node_id in payload.ids:
		GraphModel.delete_node(_dialogue, str(node_id))
	_rebuild()
	_mark_dirty()


func _ur_undelete(payload: Dictionary) -> void:
	var captures: Array = payload.captures
	for i in range(captures.size() - 1, -1, -1):
		var capture: Dictionary = captures[i]
		_dialogue.nodes.insert(mini(int(capture.index), _dialogue.nodes.size()), capture.node)
	for capture in captures:
		var restored: NarrativeDialogueNode = capture.node
		for link in capture.incoming:
			var from := _dialogue.get_node_by_id(str(link.from_id))
			if from == null:
				continue
			var choice_index := int(link.choice_index)
			if choice_index < 0:
				from.next_node_id = restored.id
			elif choice_index < from.choices.size() and from.choices[choice_index] != null:
				from.choices[choice_index].target_node_id = restored.id
		if bool(capture.was_start):
			_dialogue.start_node_id = restored.id
	_rebuild()
	_mark_dirty()


func _ur_link(payload: Dictionary) -> void:
	var port := int(payload.port)
	if port == 0:
		GraphModel.set_next(_dialogue, str(payload.from_id), str(payload.to_id))
	else:
		GraphModel.set_choice_target(_dialogue, str(payload.from_id), port - 1, str(payload.to_id))
		# keep the inline target field in sync (covers port drags AND undo)
		_sync_field_text(str(payload.from_id), "choice_target_%d" % (port - 1), str(payload.to_id))
	_refresh_connections()
	_mark_dirty()


func _ur_start(payload: Dictionary) -> void:
	_dialogue.start_node_id = str(payload.node_id)
	_update_start_styling()
	_mark_dirty()


func _ur_positions(payload: Dictionary) -> void:
	for node_id in payload.map:
		var node := _dialogue.get_node_by_id(str(node_id))
		if node != null:
			GraphModel.set_position(node, payload.map[node_id])
		var gname: String = _id_to_gname.get(str(node_id), "")
		if gname != "" and _graph.has_node(NodePath(gname)):
			(_graph.get_node(NodePath(gname)) as GraphNode).position_offset = payload.map[node_id]
	_mark_dirty()


## Sets a node's text/speaker and syncs the on-screen field (no full rebuild —
## a rebuild here would destroy whatever field the user clicked into next).
func _ur_set_field(payload: Dictionary) -> void:
	var node := _dialogue.get_node_by_id(str(payload.node_id))
	if node == null:
		return
	var field := str(payload.field)
	var value := str(payload.value)
	if field == "speaker":
		node.speaker_id = value
	elif field == "text":
		node.text = value
	_sync_field_text(str(payload.node_id), "speaker_edit" if field == "speaker" else "text_edit", value)
	_mark_dirty()


## Sets one choice's text and syncs the on-screen field (same no-rebuild rule).
func _ur_choice_text(payload: Dictionary) -> void:
	var node := _dialogue.get_node_by_id(str(payload.node_id))
	var index := int(payload.index)
	if node == null or index < 0 or index >= node.choices.size() or node.choices[index] == null:
		return
	node.choices[index].text = str(payload.value)
	_sync_field_text(str(payload.node_id), "choice_text_%d" % index, str(payload.value))
	_mark_dirty()


## Sets ALL choice texts of a node (auto-numbering do/undo payload).
func _ur_choice_texts(payload: Dictionary) -> void:
	var node := _dialogue.get_node_by_id(str(payload.node_id))
	if node == null:
		return
	var texts: PackedStringArray = payload.texts
	for i in mini(texts.size(), node.choices.size()):
		if node.choices[i] == null:
			continue
		node.choices[i].text = texts[i]
		_sync_field_text(str(payload.node_id), "choice_text_%d" % i, texts[i])
	_mark_dirty()


## Pushes a value into an inline field on the canvas, if that node/field is
## currently on screen.
func _sync_field_text(node_id: String, meta_key: String, value: String) -> void:
	var gname: String = _id_to_gname.get(node_id, "")
	if gname == "" or not _graph.has_node(NodePath(gname)):
		return
	var gnode := _graph.get_node(NodePath(gname)) as GraphNode
	if not gnode.has_meta(meta_key):
		return
	var control: Control = gnode.get_meta(meta_key)
	if is_instance_valid(control) and control.text != value:
		control.text = value


func _ur_rename(payload: Dictionary) -> void:
	var result := GraphModel.rename_node(_dialogue, str(payload.from), str(payload.to))
	if not bool(result.renamed):
		_set_status("rename failed: %s" % str(result.error), true)
		return
	_rebuild()
	_mark_dirty()


func _capture_node(node_id: String) -> Dictionary:
	var index := -1
	var node: NarrativeDialogueNode = null
	for i in _dialogue.nodes.size():
		if _dialogue.nodes[i] != null and _dialogue.nodes[i].id == node_id:
			index = i
			node = _dialogue.nodes[i]
			break
	var incoming: Array = []
	for other in _dialogue.nodes:
		if other == null or other.id == node_id:
			continue
		if other.next_node_id == node_id:
			incoming.append({"from_id": other.id, "choice_index": -1})
		for choice_index in other.choices.size():
			if other.choices[choice_index] != null and other.choices[choice_index].target_node_id == node_id:
				incoming.append({"from_id": other.id, "choice_index": choice_index})
	return {
		"node": node,
		"index": index,
		"incoming": incoming,
		"was_start": _dialogue.start_node_id == node_id,
	}


func _current_positions() -> Dictionary:
	var map := {}
	for child in _graph.get_children():
		if child is GraphNode:
			var node_id: String = _gname_to_id.get(str(child.name), "")
			if node_id != "":
				map[node_id] = child.position_offset
	return map


func _link_target(from_id: String, port: int) -> String:
	var node := _dialogue.get_node_by_id(from_id)
	if node == null:
		return ""
	if port == 0:
		return node.next_node_id
	if port - 1 < node.choices.size() and node.choices[port - 1] != null:
		return node.choices[port - 1].target_node_id
	return ""


func _on_new_dialogue_confirmed() -> void:
	var id := _new_dialog_edit.text.strip_edges()
	var dialogue := GraphModel.create_dialogue(_db, id)
	if dialogue == null:
		_set_status("cannot create dialogue '%s' (invalid or duplicate id)" % id, true)
		return
	_refresh_picker()
	open_dialogue(dialogue.id)
	_mark_dirty()


# --- internals ---


func _persist_positions() -> void:
	if _dialogue == null:
		return
	for child in _graph.get_children():
		if child is GraphNode:
			var node := _dialogue.get_node_by_id(_gname_to_id.get(str(child.name), ""))
			if node != null:
				GraphModel.set_position(node, child.position_offset)


func _selected_graph_names() -> Array:
	var names: Array = []
	for child in _graph.get_children():
		if child is GraphNode and child.selected:
			names.append(child.name)
	return names


func _refresh_picker() -> void:
	_picker.clear()
	if _db == null:
		return
	var ids: Array[String] = []
	for dialogue in _db.dialogues:
		if dialogue != null and dialogue.id != "":
			ids.append(dialogue.id)
	ids.sort()
	for id in ids:
		_picker.add_item(id)
		_picker.set_item_metadata(_picker.item_count - 1, id)


func _select_picker_item(dialogue_id: String) -> void:
	for i in _picker.item_count:
		if str(_picker.get_item_metadata(i)) == dialogue_id:
			_picker.select(i)
			return


func _show_new_dialogue_dialog() -> void:
	if _db == null:
		_set_status("load a database first", true)
		return
	_new_dialog_edit.text = ""
	_new_dialog.popup_centered(Vector2i(320, 110))
	_new_dialog_edit.grab_focus()


func _mark_dirty() -> void:
	_dirty = true


func _set_status(text: String, is_error := false) -> void:
	var prefix := "● " if _dirty else ""
	_status.text = prefix + text
	_status.modulate = Color(1.0, 0.55, 0.55) if is_error else Color(1, 1, 1, 0.7)
