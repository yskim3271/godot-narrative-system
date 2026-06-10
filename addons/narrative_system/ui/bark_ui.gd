extends Node
## Spawns short-lived speech bubbles above 2D actors (barks).
## Listens to bark_requested on the Narrative facade (or setup() target).
## One bubble per actor: a new bark replaces the previous one.

## Seconds before a bubble disappears.
@export var lifetime := 2.5
## Bubble offset from the actor's origin (pixels, 2D).
@export var bubble_offset := Vector2(0, -72)

var _api: Object
var _active: Dictionary = {}  # attach_to (Node) -> bubble (Control)


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
	api.bark_requested.connect(_on_bark)


func _unbind() -> void:
	if _api == null:
		return
	_api.bark_requested.disconnect(_on_bark)
	_api = null


func _on_bark(_character_id: String, text: String, attach_to: Node) -> void:
	if attach_to == null:
		push_warning("BarkUI: bark has no target node (actor not registered?)")
		return
	if not attach_to is Node2D:
		push_warning("BarkUI: bark target '%s' is not a Node2D (3D barks are not supported yet)" % attach_to.name)
		return
	_remove_bubble(attach_to)

	var bubble := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	var label := Label.new()
	label.name = "BarkLabel"
	label.text = text
	margin.add_child(label)
	bubble.add_child(margin)
	attach_to.add_child(bubble)
	bubble.position = bubble_offset
	# Center horizontally once the layout pass has sized the bubble.
	bubble.call_deferred("set_position", Vector2(bubble_offset.x, bubble_offset.y))
	_active[attach_to] = bubble

	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(bubble):
			if is_instance_valid(attach_to) and _active.get(attach_to) == bubble:
				_active.erase(attach_to)
			bubble.queue_free())


func _remove_bubble(attach_to: Node) -> void:
	var existing: Variant = _active.get(attach_to)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_active.erase(attach_to)
