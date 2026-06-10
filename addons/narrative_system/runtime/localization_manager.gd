class_name NarrativeLocalizationManager
extends RefCounted
## Key-based text lookup with language fallback, independent from Godot's
## project-level translations (the addon's data ships its own tables).
##
## Resolution order used by resolve():
##   1. explicit key   (current language → fallback language)
##   2. convention key (current language → fallback language)
##   3. inline text from the resource
## Unresolved EXPLICIT keys are recorded as missing (convention keys are
## optional by design and never recorded).

signal language_changed(locale: String)

var _tables: Array = []  # Array[NarrativeLocalizationTable]
var _language := "en"
var _fallback := "en"
var _sync_godot := false
var _collect_missing := true
var _missing: Dictionary = {}


func setup(database: NarrativeDatabase) -> void:
	var settings := database.get_settings()
	_tables = database.localization_tables
	_language = settings.default_language
	_fallback = settings.fallback_language
	_sync_godot = settings.sync_godot_locale
	_collect_missing = settings.collect_missing_keys


func set_language(locale: String) -> void:
	if locale == "" or locale == _language:
		return
	_language = locale
	if _sync_godot:
		TranslationServer.set_locale(locale)
	language_changed.emit(locale)


func get_language() -> String:
	return _language


func get_fallback_language() -> String:
	return _fallback


## Text for a key in the current language with fallback, or "" when missing.
func lookup(key: String) -> String:
	if key == "":
		return ""
	for locale in [_language, _fallback]:
		for table in _tables:
			if table != null and table.has_text(key, locale):
				return table.get_text(key, locale)
	return ""


## True when the key resolves in the current or fallback language.
func has_key(key: String) -> bool:
	return lookup(key) != ""


## 3-step resolution (see class docs).
func resolve(explicit_key: String, convention_key: String, inline_text: String) -> String:
	if explicit_key != "":
		var explicit := lookup(explicit_key)
		if explicit != "":
			return explicit
		_record_missing(explicit_key)
	if convention_key != "":
		var conventional := lookup(convention_key)
		if conventional != "":
			return conventional
	return inline_text


## Lookup with a code-side fallback, for UI chrome strings ("ui.*" keys).
func text_or(key: String, fallback: String) -> String:
	var localized := lookup(key)
	return localized if localized != "" else fallback


## For APIs that accept "either a key or literal text" (alerts, barks):
## returns the localized text when the input is a known key, else the input.
func resolve_text_or_key(text_or_key: String) -> String:
	var localized := lookup(text_or_key)
	return localized if localized != "" else text_or_key


## Explicit keys that failed to resolve at runtime (sorted).
func missing_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key: String in _missing:
		keys.append(key)
	keys.sort()
	return keys


func clear_missing_keys() -> void:
	_missing.clear()


func _record_missing(key: String) -> void:
	if _collect_missing:
		_missing[key] = true


# --- convention key builders (shared by runner, quest manager and tooling) ---


static func node_text_key(dialogue_id: String, node_id: String) -> String:
	return "dlg.%s.%s.text" % [dialogue_id, node_id]


static func choice_text_key(dialogue_id: String, node_id: String, choice_id: String) -> String:
	return "dlg.%s.%s.choice.%s" % [dialogue_id, node_id, choice_id]


static func character_name_key(character_id: String) -> String:
	return "char.%s.name" % character_id


static func quest_title_key(quest_id: String) -> String:
	return "quest.%s.title" % quest_id


static func quest_description_key(quest_id: String) -> String:
	return "quest.%s.desc" % quest_id


static func objective_key(quest_id: String, objective_id: String) -> String:
	return "quest.%s.obj.%s" % [quest_id, objective_id]
