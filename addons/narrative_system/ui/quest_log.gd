extends CanvasLayer
## Quest log window: active quests with objectives and tracker toggles,
## plus completed and failed sections. Toggle visibility from game code
## (call toggle()) or set toggle_action to an input action name.
##
## Binds to the Narrative facade (autoload) or any facade-shaped object
## passed to setup(). Refreshes are deferred and batched so handlers that
## change quest state never rebuild the UI they are emitting from.

## Optional input action that toggles the log (e.g. "quest_log").
@export var toggle_action := ""

var _api: Object
var _dirty := false

@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _entries: VBoxContainer = $Panel/Margin/VBox/Scroll/Entries


func _ready() -> void:
	visible = false
	if _api == null:
		var autoload := get_node_or_null("/root/Narrative")
		if autoload != null:
			setup(autoload)


func setup(api: Object) -> void:
	if _api == api:
		return
	_unbind()
	_api = api
	api.quest_updated.connect(_on_changed)
	api.language_changed.connect(_on_changed)


func _unbind() -> void:
	if _api == null:
		return
	_api.quest_updated.disconnect(_on_changed)
	_api.language_changed.disconnect(_on_changed)
	_api = null


func toggle() -> void:
	visible = not visible
	if visible and _api != null and (not _api.has_method("is_ready") or _api.is_ready()):
		_refresh_now()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action != "" and event.is_action_pressed(toggle_action):
		toggle()
		get_viewport().set_input_as_handled()


func _on_changed(_arg: Variant = null) -> void:
	if not visible or _dirty:
		return
	_dirty = true
	call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_dirty = false
	if visible:
		_refresh_now()


func _refresh_now() -> void:
	_title.text = _api.get_ui_text("ui.quest_log.title", "Quests")
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	_add_section("active", _api.get_ui_text("ui.quest_log.active", "Active"))
	_add_section("completed", _api.get_ui_text("ui.quest_log.completed", "Completed"))
	_add_section("failed", _api.get_ui_text("ui.quest_log.failed", "Failed"))


func _add_section(state: String, heading: String) -> void:
	var quest_ids: Array = _api.get_quests_in_state(state)
	if quest_ids.is_empty():
		return
	var head := Label.new()
	head.text = heading
	head.modulate = Color(1, 1, 1, 0.55)
	_entries.add_child(head)
	for quest_id in quest_ids:
		if state == "active":
			_add_active_quest(str(quest_id))
		else:
			var label := Label.new()
			label.text = "    " + _api.get_quest_title(str(quest_id))
			label.modulate = Color(1, 1, 1, 0.45) if state == "failed" else Color(1, 1, 1, 0.8)
			_entries.add_child(label)


func _add_active_quest(quest_id: String) -> void:
	var track := CheckBox.new()
	track.text = _api.get_quest_title(quest_id)
	track.button_pressed = _api.is_quest_tracked(quest_id)
	track.tooltip_text = _api.get_ui_text("ui.quest_log.track", "Show in tracker")
	track.toggled.connect(func(pressed: bool) -> void:
		_api.set_quest_tracked(quest_id, pressed))
	_entries.add_child(track)

	var description: String = _api.get_quest_description(quest_id)
	if description != "":
		var desc_label := Label.new()
		desc_label.text = "        " + description
		desc_label.modulate = Color(1, 1, 1, 0.7)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_entries.add_child(desc_label)

	for objective in _api.get_objectives_progress(quest_id):
		var line := Label.new()
		var mark := "✓" if objective.completed else "•"
		line.text = "        %s %s (%d/%d)" % [mark, objective.text, objective.count, objective.target]
		if objective.completed:
			line.modulate = Color(1, 1, 1, 0.6)
		_entries.add_child(line)
