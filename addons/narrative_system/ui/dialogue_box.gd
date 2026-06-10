extends CanvasLayer
## Reference dialogue box: speaker name, portrait (with expressions),
## typewriter text reveal and a continue indicator.
##
## Binding: automatically connects to the "Narrative" autoload when present;
## otherwise call setup() with any object exposing the runner signal/API
## surface (a NarrativeDialogueRunner or the facade). Intended to be
## restyled or replaced — all logic goes through public signals/APIs.

## Characters revealed per second; 0 or less = instant text.
@export var typewriter_chars_per_sec := 45.0
## Input action that completes the reveal / advances the line.
@export var advance_action := "ui_accept"
## Also advance on left mouse click.
@export var advance_on_click := true

var _api: Object
var _reveal_tween: Tween
var _awaiting_choices := false
var _expressions: Dictionary = {}  # character_id -> expression
var _current_speaker := ""

@onready var _portrait: TextureRect = $Panel/Margin/HBox/Portrait
@onready var _speaker_label: Label = $Panel/Margin/HBox/VBox/SpeakerLabel
@onready var _text_label: RichTextLabel = $Panel/Margin/HBox/VBox/TextLabel
@onready var _continue_indicator: Label = $Panel/Margin/HBox/VBox/ContinueIndicator


func _ready() -> void:
	visible = false
	if _api == null:
		var autoload := get_node_or_null("/root/Narrative")
		if autoload != null:
			setup(autoload)


## Binds this UI to a runner-like API (signals + advance()/select_choice()/
## get_character()/...). Rebinding replaces the previous binding (e.g. a
## test rebinding away from a not-yet-configured autoload).
func setup(api: Object) -> void:
	if _api == api:
		return
	_unbind()
	_api = api
	api.line_presented.connect(_on_line_presented)
	api.choices_presented.connect(_on_choices_presented)
	api.choice_selected.connect(_on_choice_selected)
	api.dialogue_ended.connect(_on_dialogue_ended)
	api.expression_changed.connect(_on_expression_changed)
	# Late attach while a dialogue is already running: pull the state once.
	if _api_ready() and api.is_dialogue_running():
		var node: NarrativeDialogueNode = api.get_current_node()
		if node != null:
			_on_line_presented(node.speaker_id, api.get_current_line_text())
			_awaiting_choices = api.is_waiting_for_choice()


func _unbind() -> void:
	if _api == null:
		return
	_api.line_presented.disconnect(_on_line_presented)
	_api.choices_presented.disconnect(_on_choices_presented)
	_api.choice_selected.disconnect(_on_choice_selected)
	_api.dialogue_ended.disconnect(_on_dialogue_ended)
	_api.expression_changed.disconnect(_on_expression_changed)
	_api = null


func _api_ready() -> bool:
	return not _api.has_method("is_ready") or _api.is_ready()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _awaiting_choices or _api == null:
		return
	var pressed := event.is_action_pressed(advance_action)
	if not pressed and advance_on_click and event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		pressed = mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _is_revealing():
		_finish_reveal()
	else:
		_api.advance()


func _on_line_presented(speaker_id: String, text: String) -> void:
	visible = true
	_awaiting_choices = false
	_current_speaker = speaker_id
	_speaker_label.text = _api.get_character_display_name(speaker_id)
	_speaker_label.visible = _speaker_label.text != ""
	_update_portrait()
	_text_label.text = text
	_start_reveal()


func _on_choices_presented(_choices: Array) -> void:
	_awaiting_choices = true
	_continue_indicator.visible = false


func _on_choice_selected(_choice_id: String) -> void:
	_awaiting_choices = false


func _on_dialogue_ended(_dialogue_id: String) -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
	visible = false
	_expressions.clear()
	_current_speaker = ""


func _on_expression_changed(character_id: String, expression: String) -> void:
	_expressions[character_id] = expression
	if character_id == _current_speaker:
		_update_portrait()


func _update_portrait() -> void:
	var texture: Texture2D = null
	if _current_speaker != "":
		var character: NarrativeCharacter = _api.get_character(_current_speaker)
		if character != null:
			texture = character.get_portrait_for(str(_expressions.get(_current_speaker, "")))
	_portrait.texture = texture
	_portrait.visible = texture != null


func _start_reveal() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
	_continue_indicator.visible = false
	var total := _text_label.get_total_character_count()
	if typewriter_chars_per_sec <= 0.0 or total == 0:
		_text_label.visible_ratio = 1.0
		_on_reveal_finished()
		return
	_text_label.visible_characters = 0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(_text_label, "visible_characters", total, float(total) / typewriter_chars_per_sec)
	_reveal_tween.finished.connect(_on_reveal_finished)


func _finish_reveal() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
	_text_label.visible_ratio = 1.0
	_on_reveal_finished()


func _is_revealing() -> bool:
	return _reveal_tween != null and _reveal_tween.is_running()


func _on_reveal_finished() -> void:
	_continue_indicator.visible = not _awaiting_choices
