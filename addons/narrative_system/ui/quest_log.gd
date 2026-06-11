extends CanvasLayer
## Quest log window: active quests with objectives, tracker toggles and an
## optional Abandon button, plus completed and failed sections (repeat
## completions show as "×N"). Toggle visibility from game code (call
## toggle()) or set toggle_action to an input action name.
##
## Binds to the Narrative facade (autoload) or any facade-shaped object
## passed to setup(). Refreshes are deferred and batched so handlers that
## change quest state never rebuild the UI they are emitting from.

## Optional input action that toggles the log (e.g. "quest_log").
@export var toggle_action := ""
## Show an Abandon button on active quests (calls abandon_quest(); hidden
## automatically when the bound facade does not expose it).
@export var show_abandon_button := true

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
			label.text = "    " + _title_with_completions(str(quest_id))
			label.modulate = Color(1, 1, 1, 0.45) if state == "failed" else Color(1, 1, 1, 0.8)
			_entries.add_child(label)


## Quest title plus a "×N" repeat-completion badge (shown from the second
## completion on, so one-shot quests stay clean).
func _title_with_completions(quest_id: String) -> String:
	var title: String = _api.get_quest_title(quest_id)
	if _api.has_method("get_times_completed"):
		var completions: int = _api.get_times_completed(quest_id)
		if completions > 1:
			title += " ×%d" % completions
	return title


func _add_active_quest(quest_id: String) -> void:
	var row := HBoxContainer.new()
	_entries.add_child(row)

	var track := CheckBox.new()
	track.text = _title_with_completions(quest_id)
	track.button_pressed = _api.is_quest_tracked(quest_id)
	track.tooltip_text = _api.get_ui_text("ui.quest_log.track", "Show in tracker")
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.toggled.connect(func(pressed: bool) -> void:
		_api.set_quest_tracked(quest_id, pressed))
	row.add_child(track)

	if show_abandon_button and _api.has_method("abandon_quest"):
		var abandon := Button.new()
		abandon.text = _api.get_ui_text("ui.quest_log.abandon", "Abandon")
		abandon.tooltip_text = _api.get_ui_text("ui.quest_log.abandon_tip", "Drop this quest (progress is lost)")
		abandon.pressed.connect(func() -> void:
			_api.abandon_quest(quest_id))
		row.add_child(abandon)

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
