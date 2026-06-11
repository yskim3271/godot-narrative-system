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
## Slot 1 is the portless text preview row.
##
## Field editing happens in the Inspector: selecting a graph node opens its
## NarrativeDialogueNode there. Structural changes made in the Inspector
## (e.g. added choices) appear after Refresh / re-opening the tab.
## NOTE: no undo/redo yet (see docs/graph_editor.md).

const GraphModel := preload("dialogue_graph_model.gd")
const SETTING_DATABASE_PATH := "narrative_system/database_path"

const COLOR_IN := Color(0.78, 0.78, 0.78)
const COLOR_NEXT := Color(0.55, 0.78, 1.0)
const COLOR_CHOICE := Color(1.0, 0.84, 0.4)
const MENU_ADD_NODE := 0

var _db: NarrativeDatabase
var _dialogue: NarrativeDialogue
var _dirty := false
var _gname_to_id := {}
var _id_to_gname := {}
var _next_gname := 0
var _popup_graph_pos := Vector2.ZERO

var _graph: GraphEdit
var _picker: OptionButton
var _status: Label
var _context_menu: PopupMenu
var _new_dialog: ConfirmationDialog
var _new_dialog_edit: LineEdit


func _init() -> void:
	name = "NarrativeGraphEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _ready() -> void:
	if Engine.is_editor_hint():
		reload_database()


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


func current_dialogue() -> NarrativeDialogue:
	return _dialogue


func get_graph_edit() -> GraphEdit:
	return _graph


func graph_name_for(node_id: String) -> StringName:
	return StringName(_id_to_gname.get(node_id, ""))


## Adds a node at a canvas position and shows it.
func add_node_at(position: Vector2) -> NarrativeDialogueNode:
	if _dialogue == null:
		_set_status("open a dialogue first", true)
		return null
	var node := GraphModel.add_node(_dialogue, "", position)
	if node == null:
		return null
	_spawn_graph_node(node)
	_update_start_styling()
	_mark_dirty()
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
	if node_id != "" and GraphModel.set_start(_dialogue, node_id):
		_update_start_styling()
		_mark_dirty()
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
	_graph.end_node_move.connect(_on_end_node_move)
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


func _toolbar_button(parent: Control, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
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
	gnode.title = node.id
	gnode.position_offset = GraphModel.get_position(node)

	# slot 0 — header: in (previous) / out (next)
	var header := Label.new()
	header.text = _header_text(node)
	gnode.add_child(header)
	gnode.set_slot(0, true, 0, COLOR_IN, true, 0, COLOR_NEXT)

	# slot 1 — text preview, no ports
	var preview := Label.new()
	preview.text = _ellipsis(node.text, 90)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(240, 0)
	preview.modulate = Color(1, 1, 1, 0.8)
	gnode.add_child(preview)

	# slots 2.. — one output port per choice
	for i in node.choices.size():
		var choice := node.choices[i]
		var row := Label.new()
		var label_text := "(null choice)"
		if choice != null:
			label_text = choice.text if choice.text != "" else choice.id
		row.text = "▸ " + _ellipsis(label_text, 42)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gnode.add_child(row)
		gnode.set_slot(2 + i, false, 0, COLOR_IN, true, 0, COLOR_CHOICE)

	_graph.add_child(gnode)
	return gnode


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


func _ellipsis(text: String, max_length: int) -> String:
	var single_line := text.replace("\n", " ")
	if single_line.length() <= max_length:
		return single_line
	return single_line.substr(0, maxi(max_length - 1, 1)) + "…"


func _header_text(node: NarrativeDialogueNode) -> String:
	var speaker := node.speaker_id if node.speaker_id != "" else "(narrator)"
	var badges := ""
	if node.conditions.strip_edges() != "":
		badges += " ❓"
	if node.actions.strip_edges() != "":
		badges += " ⚡"
	if node.sequencer_commands.strip_edges() != "":
		badges += " 🎬"
	return speaker + badges


# --- gesture handlers (also called directly by tests) ---


func _on_connection_request(from_name: StringName, from_port: int, to_name: StringName, to_port: int) -> void:
	if to_port != 0 or _dialogue == null:
		return
	var from_id: String = _gname_to_id.get(str(from_name), "")
	var to_id: String = _gname_to_id.get(str(to_name), "")
	if from_id == "" or to_id == "":
		return
	var ok := false
	if from_port == 0:
		ok = GraphModel.set_next(_dialogue, from_id, to_id)
	else:
		ok = GraphModel.set_choice_target(_dialogue, from_id, from_port - 1, to_id)
	if ok:
		_refresh_connections()
		_mark_dirty()


func _on_disconnection_request(from_name: StringName, from_port: int, _to_name: StringName, _to_port: int) -> void:
	if _dialogue == null:
		return
	var from_id: String = _gname_to_id.get(str(from_name), "")
	if from_id == "":
		return
	var ok := false
	if from_port == 0:
		ok = GraphModel.set_next(_dialogue, from_id, "")
	else:
		ok = GraphModel.set_choice_target(_dialogue, from_id, from_port - 1, "")
	if ok:
		_refresh_connections()
		_mark_dirty()


func _on_delete_nodes_request(names: Array) -> void:
	if _dialogue == null or names.is_empty():
		return
	var removed := 0
	var cleaned := 0
	for name in names:
		var node_id: String = _gname_to_id.get(str(name), "")
		if node_id == "":
			continue
		var report := GraphModel.delete_node(_dialogue, node_id)
		if bool(report.removed):
			removed += 1
			cleaned += int(report.cleaned_links)
	if removed > 0:
		_rebuild()
		_mark_dirty()
		_set_status("deleted %d node(s), cleared %d link(s)" % [removed, cleaned])


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


func _on_end_node_move() -> void:
	_persist_positions()
	_mark_dirty()


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
