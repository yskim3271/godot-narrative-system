extends CanvasLayer
## Queued toast notifications (top-center). One alert shows at a time;
## further alerts wait in a queue. Subscribes to alert_requested on the
## Narrative facade (or any object passed to setup()).

@export var display_seconds := 2.5
@export var fade_seconds := 0.4
@export var max_queue := 8

var _api: Object
var _queue: Array[String] = []
var _showing := false

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label


func _ready() -> void:
	_panel.visible = false
	if _api == null:
		var autoload := get_node_or_null("/root/Narrative")
		if autoload != null:
			setup(autoload)


func setup(api: Object) -> void:
	if _api == api:
		return
	_unbind()
	_api = api
	api.alert_requested.connect(enqueue)


func _unbind() -> void:
	if _api == null:
		return
	_api.alert_requested.disconnect(enqueue)
	_api = null


## Queues an alert text (already localized by the facade/context).
func enqueue(text: String) -> void:
	if _queue.size() >= max_queue:
		_queue.pop_front()
	_queue.append(text)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		_panel.visible = false
		return
	_showing = true
	_label.text = _queue.pop_front()
	_panel.visible = true
	_panel.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(display_seconds)
	tween.tween_property(_panel, "modulate:a", 0.0, fade_seconds)
	tween.finished.connect(_show_next, CONNECT_ONE_SHOT)
