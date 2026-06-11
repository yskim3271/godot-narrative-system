@tool
class_name NarrativeDatabase
extends Resource
## Root resource holding all narrative data: characters, dialogues, quests,
## variables, localization tables and settings.
##
## Immutable at runtime. Id lookup indexes are runtime caches (not exported)
## that rebuild when array sizes change; duplicate ids are reported once and
## the first definition wins.

@export var characters: Array[NarrativeCharacter] = []
@export var dialogues: Array[NarrativeDialogue] = []
@export var quests: Array[NarrativeQuest] = []
@export var variables: Array[NarrativeVariable] = []
@export var localization_tables: Array[NarrativeLocalizationTable] = []
@export var settings: NarrativeSettings

var _char_index := {}
var _dialogue_index := {}
var _quest_index := {}
var _variable_index := {}
var _index_counts := {}
var _default_settings: NarrativeSettings


func get_character(character_id: String) -> NarrativeCharacter:
	return _lookup("characters", characters, character_id)


func get_dialogue(dialogue_id: String) -> NarrativeDialogue:
	return _lookup("dialogues", dialogues, dialogue_id)


func get_quest(quest_id: String) -> NarrativeQuest:
	return _lookup("quests", quests, quest_id)


func get_variable(variable_id: String) -> NarrativeVariable:
	return _lookup("variables", variables, variable_id)


## Editor/import tooling: call after REPLACING entries in place (the lazy
## id indexes only auto-invalidate when an array's size changes).
func invalidate_indexes() -> void:
	_index_counts = {}


## Settings, falling back to defaults when none are assigned in the database.
func get_settings() -> NarrativeSettings:
	if settings != null:
		return settings
	if _default_settings == null:
		_default_settings = NarrativeSettings.new()
	return _default_settings


func _lookup(category: String, items: Array, item_id: String) -> Resource:
	var index := _ensure_index(category, items)
	return index.get(item_id)


func _ensure_index(category: String, items: Array) -> Dictionary:
	var index: Dictionary = _index_for(category)
	if int(_index_counts.get(category, -1)) == items.size():
		return index
	index.clear()
	for item in items:
		if item == null:
			continue
		var item_id: String = item.id
		if item_id == "":
			push_error("NarrativeDatabase: %s entry with empty id ('%s') — skipped" % [category, item.resource_path])
			continue
		if index.has(item_id):
			push_error("NarrativeDatabase: duplicate %s id '%s' (first definition wins)" % [category, item_id])
			continue
		index[item_id] = item
	_index_counts[category] = items.size()
	return index


func _index_for(category: String) -> Dictionary:
	match category:
		"characters":
			return _char_index
		"dialogues":
			return _dialogue_index
		"quests":
			return _quest_index
		_:
			return _variable_index
