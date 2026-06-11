@tool
class_name NarrativeChoice
extends Resource
## A player response option attached to a [NarrativeDialogueNode].
##
## Pure authoring data — never mutated at runtime.

## Unique id within the owning node (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Choice label (default language). Localizable via localized_text_key or the
## convention key "dlg.{dialogue_id}.{node_id}.choice.{id}".
@export_multiline var text := ""
## Optional explicit localization key for the label.
@export var localized_text_key := ""
## Condition DSL expression gating this choice. Empty = always available.
@export_multiline var condition := ""
## When the condition fails: false = hide the choice entirely,
## true = show it disabled (grayed out).
@export var show_disabled := false
## Action DSL statements executed when this choice is selected.
@export_multiline var actions := ""
## Node to jump to after selection. Empty = end the dialogue.
@export var target_node_id := ""
## Free-form authoring metadata.
@export var metadata: Dictionary = {}
