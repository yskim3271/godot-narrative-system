class_name NarrativeLocalizationTable
extends Resource
## Key → locale → text table used by the LocalizationManager.
##
## Stored inside the database so dialogue data ships with its translations
## (no dependency on project-level CSV imports). CSV import/export tooling
## reads/writes [member entries] directly.

## Table id (a database may split tables, e.g. "dialogue" / "ui").
@export var id := "main"
## key -> { locale -> text }, e.g.
## { "dlg.intro.n1.text": { "en": "Halt!", "ko": "멈춰라!" } }
@export var entries: Dictionary[String, Dictionary] = {}


## Text for key in the given locale, or "" when missing.
func get_text(key: String, locale: String) -> String:
	var locales: Dictionary = entries.get(key, {})
	return str(locales.get(locale, ""))


func has_text(key: String, locale: String) -> bool:
	var locales: Dictionary = entries.get(key, {})
	return locales.has(locale) and str(locales[locale]) != ""


## Editor/import tooling helper (never called at runtime).
func set_text(key: String, locale: String, text: String) -> void:
	if not entries.has(key):
		entries[key] = {}
	entries[key][locale] = text


## All locales that appear anywhere in the table.
func collect_locales() -> PackedStringArray:
	var found := {}
	for key: String in entries:
		for locale: String in entries[key]:
			found[locale] = true
	var result := PackedStringArray()
	for locale: String in found:
		result.append(locale)
	result.sort()
	return result
