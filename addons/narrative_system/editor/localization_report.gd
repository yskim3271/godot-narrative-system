@tool
extends RefCounted
## Translation coverage analysis for a NarrativeDatabase (editor tooling,
## headless-testable — no editor dependencies).
##
## A "unit" is one translatable text: node text, choice text, character
## display name, quest title/description, objective description. Each unit
## resolves to exactly one key — its explicit *_key when set, else the
## convention key — and is checked against every locale of the database
## (locales appearing in tables + default + fallback language).
##
## Coverage rule (mirrors NarrativeLocalizationManager.resolve):
##  - a unit is covered in a locale when its key has text in that locale
##  - the DEFAULT language is additionally covered by inline text (inline
##    text IS the default-language text by contract)
## Units with nothing authored at all (no inline text, no explicit key and
## no table entry under the convention key) are skipped — there is nothing
## to translate yet.


## Returns:
## {
##   locales: PackedStringArray,           # all checked locales, sorted
##   default_language: String,
##   units: int,                           # translatable units found
##   rows: Array[Dictionary],              # units missing in >= 1 locale:
##     { where: String, key: String, missing: PackedStringArray,
##       ref: Dictionary }                 # ref is parse_where-shaped
##   missing_by_locale: Dictionary,        # locale -> missing unit count
## }
static func build(db: NarrativeDatabase) -> Dictionary:
	var settings := db.get_settings()
	var locales := _collect_locales(db, settings)
	var report := {
		"locales": locales,
		"default_language": settings.default_language,
		"units": 0,
		"rows": [] as Array[Dictionary],
		"missing_by_locale": {},
	}
	for locale in locales:
		report.missing_by_locale[locale] = 0

	for character in db.characters:
		if character == null or character.id == "":
			continue
		_check_unit(db, report,
			character.display_name_key,
			NarrativeLocalizationManager.character_name_key(character.id),
			character.display_name if character.display_name != "" else character.id,
			"character '%s'" % character.id,
			{"category": "character", "id": character.id})

	for dialogue in db.dialogues:
		if dialogue == null or dialogue.id == "":
			continue
		for node in dialogue.nodes:
			if node == null or node.id == "":
				continue
			var node_where := "dialogue '%s' > node '%s'" % [dialogue.id, node.id]
			_check_unit(db, report,
				node.localized_text_key,
				NarrativeLocalizationManager.node_text_key(dialogue.id, node.id),
				node.text, node_where + " > text",
				{"category": "dialogue", "id": dialogue.id, "node": node.id})
			for choice in node.choices:
				if choice == null or choice.id == "":
					continue
				_check_unit(db, report,
					choice.localized_text_key,
					NarrativeLocalizationManager.choice_text_key(dialogue.id, node.id, choice.id),
					choice.text,
					"%s > choice '%s' > text" % [node_where, choice.id],
					{"category": "dialogue", "id": dialogue.id, "node": node.id, "choice": choice.id})

	for quest in db.quests:
		if quest == null or quest.id == "":
			continue
		var quest_where := "quest '%s'" % quest.id
		var quest_ref := {"category": "quest", "id": quest.id}
		_check_unit(db, report,
			quest.title_key,
			NarrativeLocalizationManager.quest_title_key(quest.id),
			quest.title if quest.title != "" else quest.id,
			quest_where + " > title", quest_ref)
		_check_unit(db, report,
			quest.description_key,
			NarrativeLocalizationManager.quest_description_key(quest.id),
			quest.description, quest_where + " > description", quest_ref)
		for objective in quest.objectives:
			if objective == null or objective.id == "":
				continue
			_check_unit(db, report,
				objective.description_key,
				NarrativeLocalizationManager.objective_key(quest.id, objective.id),
				objective.description,
				"%s > objective '%s'" % [quest_where, objective.id],
				{"category": "quest", "id": quest.id, "objective": objective.id})
	return report


static func _check_unit(
	db: NarrativeDatabase,
	report: Dictionary,
	explicit_key: String,
	convention_key: String,
	inline_text: String,
	where: String,
	ref: Dictionary,
) -> void:
	var key := explicit_key if explicit_key != "" else convention_key
	if inline_text == "" and explicit_key == "" and not _key_exists(db, key):
		return  # nothing authored yet
	report.units += 1
	var missing := PackedStringArray()
	for locale: String in report.locales:
		if _has_text(db, key, locale):
			continue
		if locale == str(report.default_language) and inline_text != "":
			continue
		missing.append(locale)
		report.missing_by_locale[locale] = int(report.missing_by_locale[locale]) + 1
	if not missing.is_empty():
		report.rows.append({"where": where, "key": key, "missing": missing, "ref": ref})


static func _collect_locales(db: NarrativeDatabase, settings: NarrativeSettings) -> PackedStringArray:
	var found := {settings.default_language: true, settings.fallback_language: true}
	for table in db.localization_tables:
		if table == null:
			continue
		for locale in table.collect_locales():
			found[locale] = true
	var locales := PackedStringArray()
	for locale: String in found:
		if locale != "":
			locales.append(locale)
	locales.sort()
	return locales


static func _has_text(db: NarrativeDatabase, key: String, locale: String) -> bool:
	for table in db.localization_tables:
		if table != null and table.has_text(key, locale):
			return true
	return false


static func _key_exists(db: NarrativeDatabase, key: String) -> bool:
	for table in db.localization_tables:
		if table != null and table.entries.has(key):
			return true
	return false
