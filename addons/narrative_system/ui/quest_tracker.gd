extends CanvasLayer
## Quest tracker HUD (top-right): tracked active quests with objective
## progress. Hides itself when nothing is tracked. Binds to the Narrative
## facade (autoload) or any facade-shaped object passed to setup().

var _api: Object
var _dirty := false

@onready var _box: VBoxContainer = $Box


func _ready() -> void:
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
	if not _api.has_method("is_ready") or _api.is_ready():
		_refresh_now()
	else:
		visible = false


func _unbind() -> void:
	if _api == null:
		return
	_api.quest_updated.disconnect(_on_changed)
	_api.language_changed.disconnect(_on_changed)
	_api = null


func _on_changed(_arg: Variant = null) -> void:
	if _dirty:
		return
	_dirty = true
	call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_dirty = false
	_refresh_now()


func _refresh_now() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var tracked: Array = _api.get_tracked_quests()
	visible = not tracked.is_empty()
	for quest_id in tracked:
		var title := Label.new()
		title.text = _api.get_quest_title(str(quest_id))
		title.add_theme_font_size_override("font_size", 17)
		_box.add_child(title)
		for objective in _api.get_objectives_progress(str(quest_id)):
			var line := Label.new()
			var mark := "✓" if objective.completed else "•"
			line.text = "  %s %s (%d/%d)" % [mark, objective.text, objective.count, objective.target]
			line.modulate = Color(1, 1, 1, 0.65 if objective.completed else 0.9)
			_box.add_child(line)
