@tool
class_name NarrativeQuest
extends Resource
## A quest definition: objectives, prerequisites and rewards.
##
## IMPORTANT: authoring data only. The runtime state
## (inactive/active/completed/failed, objective progress, tracked flag)
## lives in NarrativeState and is managed by the QuestManager — every quest
## begins "inactive" and resources are never mutated at runtime.

## Unique id (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Quest title (default language). Localizable via title_key or the
## convention key "quest.{id}.title".
@export var title := ""
## Optional explicit localization key for the title.
@export var title_key := ""
## Quest description (default language). Localizable via description_key or
## the convention key "quest.{id}.desc".
@export_multiline var description := ""
## Optional explicit localization key for the description.
@export var description_key := ""
## Objectives, all of which must be completed before complete_quest()
## succeeds (unless force-completed).
@export var objectives: Array[NarrativeQuestObjective] = []
## Quest ids that must be in "completed" state before this quest can start.
@export var prerequisites: PackedStringArray = []
## Action DSL statements executed when the quest completes
## (e.g. [code]player.gold += 100; alert("ui.alert.reward")[/code]).
@export_multiline var rewards := ""
## Show this quest in the QuestTracker HUD automatically when started.
@export var auto_track := true
## Repeatable quests can be started again after being completed or failed
## (objective progress resets; the completion count is kept — see
## QuestManager.get_times_completed()).
@export var repeatable := false
## Free-form grouping tag for quest log filtering (e.g. "main", "side",
## "daily"). Purely organizational — the runtime never interprets it.
@export var category := ""
## Free-form authoring metadata.
@export var metadata: Dictionary = {}


## Objective lookup by id. Returns null when missing.
func get_objective_by_id(objective_id: String) -> NarrativeQuestObjective:
	for objective in objectives:
		if objective != null and objective.id == objective_id:
			return objective
	return null
