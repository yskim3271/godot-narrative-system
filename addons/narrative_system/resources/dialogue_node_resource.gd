@tool
class_name NarrativeDialogueNode
extends Resource
## One line of dialogue inside a [NarrativeDialogue] graph.
##
## Pure authoring data — never mutated at runtime.

## Unique id within the owning dialogue (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Character id of the speaker. Empty = narrator (no name/portrait).
@export var speaker_id := ""
## Line text (default language). Localizable via localized_text_key or the
## convention key "dlg.{dialogue_id}.{id}.text".
@export_multiline var text := ""
## Optional explicit localization key for the line text.
@export var localized_text_key := ""
## Condition DSL expression. When false, this node is skipped and the runner
## hops to next_node_id (ends the dialogue if there is none).
@export_multiline var conditions := ""
## Action DSL statements executed when the node is entered (after the
## condition passed, before the line is presented).
@export_multiline var actions := ""
## Sequencer command lines started alongside the presented line
## (one call per line or separated by ';'), e.g. [code]wait(0.5)[/code].
@export_multiline var sequencer_commands := ""
## Player response options. When at least one is visible, the runner waits
## for select_choice() instead of advance().
@export var choices: Array[NarrativeChoice] = []
## Node to advance to when there are no (visible) choices.
## Empty = end the dialogue on advance().
@export var next_node_id := ""
## Free-form authoring metadata. Recognized key:
## (none yet — reserved for future use)
@export var metadata: Dictionary = {}
