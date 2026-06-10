class_name NarrativeCharacter
extends Resource
## A speaker/actor definition: display name, portrait and expressions.
##
## Pure authoring data — never mutated at runtime.

## Unique id referenced by DialogueNode.speaker_id (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Name shown in dialogue UIs. Localizable via display_name_key or the
## convention key "char.{id}.name".
@export var display_name := ""
## Optional explicit localization key for the display name.
@export var display_name_key := ""
## Default portrait, used when no expression override applies.
@export var portrait: Texture2D
## Expression name -> portrait override (e.g. "angry", "happy").
@export var expressions: Dictionary[String, Texture2D] = {}
## Optional default voice stream (used by sequencer play_audio with no path).
@export var default_voice: AudioStream
## Free-form authoring metadata.
@export var metadata: Dictionary = {}


## Portrait for the given expression, falling back to the default portrait.
func get_portrait_for(expression: String) -> Texture2D:
	if expression != "" and expressions.has(expression):
		return expressions[expression]
	return portrait
