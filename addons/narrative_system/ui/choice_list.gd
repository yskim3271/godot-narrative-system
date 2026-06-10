extends CanvasLayer
## Reference choice list: builds focusable buttons from choices_presented.
## Keyboard/gamepad: first enabled button grabs focus, arrow keys navigate
## (default Button focus behavior), ui_accept selects. Disabled choices
## (condition not met, show_disabled = true) render grayed out.

## Prefix choices with "1. ", "2. ", ...
@export var number_choices := true

var _api: Object

@onready var _container: VBoxContainer = $Panel/Margin/Choices


func _ready() -> void:
	visible = false
	if _api == null:
		var autoload := get_node_or_null("/root/Narrative")
		if autoload != null:
			setup(autoload)


## Binds to a runner-like API. Call once; for tests pass context.runner.
func setup(api: Object) -> void:
	if _api != null:
		push_warning("ChoiceList: already bound — rebinding is not supported")
		return
	_api = api
	api.choices_presented.connect(_on_choices_presented)
	api.choice_selected.connect(_on_choice_selected)
	api.dialogue_ended.connect(_on_dialogue_ended)
	if api.is_waiting_for_choice():
		_on_choices_presented(api.get_available_choices())


func _on_choices_presented(choices: Array) -> void:
	_clear()
	var first_enabled: Button = null
	for i in choices.size():
		var data: Dictionary = choices[i]
		var button := Button.new()
		button.text = ("%d. %s" % [i + 1, data.text]) if number_choices else str(data.text)
		button.disabled = not bool(data.enabled)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var choice_id := str(data.id)
		button.pressed.connect(func() -> void: _api.select_choice(choice_id))
		_container.add_child(button)
		if first_enabled == null and not button.disabled:
			first_enabled = button
	visible = true
	if first_enabled != null:
		first_enabled.grab_focus()


func _on_choice_selected(_choice_id: String) -> void:
	_hide()


func _on_dialogue_ended(_dialogue_id: String) -> void:
	_hide()


func _hide() -> void:
	visible = false
	_clear()


func _clear() -> void:
	for child in _container.get_children():
		_container.remove_child(child)
		child.queue_free()
