@tool
class_name NarrativeQuestObjective
extends Resource
## One objective inside a [NarrativeQuest].
##
## IMPORTANT: this resource holds authoring data and INITIAL values only.
## Runtime progress (current count / completion) lives in NarrativeState,
## copied on first touch — resources are never mutated at runtime.

## Unique id within the owning quest (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Objective text shown in quest log/tracker (default language).
## Localizable via description_key or the convention key
## "quest.{quest_id}.obj.{id}".
@export_multiline var description := ""
## Optional explicit localization key for the description.
@export var description_key := ""
## Count needed to complete this objective (e.g. kill 5 rats). Minimum 1.
@export var target_count := 1
## Initial progress count when the quest starts (normally 0).
@export var initial_count := 0
## Optional condition DSL (e.g. [code]gold >= 100[/code]). While the owning
## quest is active, the objective auto-completes (count jumps to
## target_count) as soon as this evaluates true — checked on quest start and
## whenever a narrative variable changes. Empty = manual progress only.
@export_multiline var auto_complete_condition := ""
## Free-form authoring metadata.
@export var metadata: Dictionary = {}
