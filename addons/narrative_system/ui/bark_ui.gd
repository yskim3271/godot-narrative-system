extends Node
## Spawns short-lived speech bubbles above actors (barks).
## Listens to bark_requested on the Narrative facade (or setup() target).
## One bubble per actor: a new bark replaces the previous one.
##
## 2D actors (Node2D): the bubble is a child of the actor at bubble_offset.
## 3D actors (Node3D): the bubble is a screen-space child of THIS node and
## follows the actor's projected position every frame (hidden while the
## actor is behind the active Camera3D).

## Seconds before a bubble disappears.
@export var lifetime := 2.5
## Bubble offset from a 2D actor's origin (pixels).
@export var bubble_offset := Vector2(0, -72)
## Bubble anchor above a 3D actor's origin (world units).
@export var bubble_offset_3d := Vector3(0, 2.2, 0)

var _api: Object
var _active: Dictionary = {}  # attach_to (Node) -> bubble (Control)
var _active_3d: Dictionary = {}  # attach_to (Node3D) -> bubble, projected in _process


func _ready() -> void:
	set_process(false)
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
	if attach_to is Node3D:
		_spawn_3d(attach_to as Node3D, text)
		return
	if not attach_to is Node2D:
		push_warning("BarkUI: bark target '%s' is neither a Node2D nor a Node3D" % attach_to.name)
		return
	_remove_bubble(attach_to)
	var bubble := _build_bubble(text)
	attach_to.add_child(bubble)
	bubble.position = bubble_offset
	# Center horizontally once the layout pass has sized the bubble.
	bubble.call_deferred("set_position", Vector2(bubble_offset.x, bubble_offset.y))
	_active[attach_to] = bubble
	_schedule_expiry(attach_to, bubble)


func _spawn_3d(attach_to: Node3D, text: String) -> void:
	_remove_bubble(attach_to)
	var bubble := _build_bubble(text)
	add_child(bubble)  # screen space: this node owns it, _process projects it
	_active[attach_to] = bubble
	_active_3d[attach_to] = bubble
	set_process(true)
	_project_3d_bubble(attach_to, bubble)
	_schedule_expiry(attach_to, bubble)


func _process(_delta: float) -> void:
	if _active_3d.is_empty():
		set_process(false)
		return
	for actor in _active_3d.keys():
		var bubble: Control = _active_3d[actor]
		if not is_instance_valid(bubble):
			_active_3d.erase(actor)
			continue
		if not is_instance_valid(actor):
			bubble.visible = false
			continue
		_project_3d_bubble(actor, bubble)


func _project_3d_bubble(actor: Node3D, bubble: Control) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not actor.is_inside_tree():
		bubble.visible = false
		return
	var world := actor.global_position + bubble_offset_3d
	if camera.is_position_behind(world):
		bubble.visible = false
		return
	bubble.visible = true
	var screen := camera.unproject_position(world)
	bubble.position = screen - Vector2(bubble.size.x * 0.5, bubble.size.y)


func _build_bubble(text: String) -> PanelContainer:
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
	return bubble


func _schedule_expiry(attach_to: Node, bubble: Control) -> void:
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(bubble):
			if is_instance_valid(attach_to) and _active.get(attach_to) == bubble:
				_active.erase(attach_to)
				_active_3d.erase(attach_to)
			bubble.queue_free())


func _remove_bubble(attach_to: Node) -> void:
	var existing: Variant = _active.get(attach_to)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_active.erase(attach_to)
	_active_3d.erase(attach_to)
