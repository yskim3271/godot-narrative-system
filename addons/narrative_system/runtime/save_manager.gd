@tool
class_name NarrativeSaveManager
extends RefCounted
## Versioned, human-readable JSON save/load for the whole narrative state
## (variables, quests, seen nodes, history, current dialogue position,
## language, game custom data). Schema: docs/save_format.md.
##
## Safety properties:
##  - atomic writes (tmp -> rename) with one .bak rotation of the previous save
##  - corrupted files are quarantined (*.corrupt-<unix>), state stays untouched
##  - newer save_version than this build refuses to load
##  - migration chain for older versions; a missing step refuses the load
##  - pure JSON only: loading never instantiates resources or scripts

const NSVersion := preload("../version.gd")
const Migrations := preload("save_migrations.gd")
## "inactive" entries exist for abandoned quests with a completion history.
const VALID_QUEST_STATES: PackedStringArray = ["inactive", "active", "completed", "failed"]

var save_dir := "user://saves"
## from_version (int) -> Callable; replaceable for tests / game extensions.
var migrations: Dictionary = Migrations.defaults()

var _database: NarrativeDatabase
var _state: NarrativeState
var _localization: NarrativeLocalizationManager
var _runner: NarrativeDialogueRunner


func setup(
	database: NarrativeDatabase,
	state: NarrativeState,
	localization: NarrativeLocalizationManager,
	runner: NarrativeDialogueRunner,
) -> void:
	_database = database
	_state = state
	_localization = localization
	_runner = runner


func save_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]


func has_save(slot := "save") -> bool:
	return FileAccess.file_exists(save_path(slot))


func delete_save(slot := "save") -> bool:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## Pure snapshot of the current runtime state (no I/O).
func capture() -> Dictionary:
	var variables := {}
	for variable_id: String in _state.variable_values():
		if _state.is_persistent(variable_id):
			variables[variable_id] = _state.get_value(variable_id)

	var seen := {}
	for dialogue_id: String in _state.seen:
		var node_ids: Array = []
		for node_id: String in _state.seen[dialogue_id]:
			node_ids.append(node_id)
		node_ids.sort()  # deterministic output for stable diffs
		seen[dialogue_id] = node_ids

	return {
		"save_version": NSVersion.SAVE_VERSION,
		"plugin_version": NSVersion.VERSION,
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"language": _localization.get_language(),
		"variables": variables,
		"quests": _state.quest_states.duplicate(true),
		"dialogue": {
			"seen_nodes": seen,
			"history": _state.history.duplicate(true),
			"current": null if _state.current_dialogue.is_empty() else _state.current_dialogue.duplicate(),
		},
		"custom": _state.custom_data.duplicate(true),
	}


## Serializes and writes atomically. Returns OK or an Error code
## (ERR_BUSY while a dialogue transition is processing).
func save_game(slot := "save") -> Error:
	if _runner != null and not _runner.is_settled():
		push_error("Narrative: save_game refused — a dialogue transition is processing (save from signal handlers between lines instead)")
		return ERR_BUSY
	var dir_error := DirAccess.make_dir_recursive_absolute(save_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("Narrative: cannot create save directory '%s' (%s)" % [save_dir, error_string(dir_error)])
		return dir_error

	var path := save_path(slot)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("Narrative: cannot write '%s' (%s)" % [tmp_path, error_string(open_error)])
		return open_error
	file.store_string(JSON.stringify(capture(), "\t") + "\n")
	file.close()

	if FileAccess.file_exists(path):
		var bak_path := path + ".bak"
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		DirAccess.rename_absolute(path, bak_path)
	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		push_error("Narrative: failed to finalize save '%s' (%s) — previous save preserved" % [path, error_string(rename_error)])
		return rename_error
	return OK


## Reads, migrates and applies a save file. State is untouched on failure.
func load_game(slot := "save") -> Error:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		push_error("Narrative: no save file at '%s'" % path)
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var quarantine := "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.rename_absolute(path, quarantine)
		push_error("Narrative: save file '%s' is corrupted — quarantined to '%s', state untouched" % [path, quarantine])
		return ERR_FILE_CORRUPT
	return apply(parsed)


## Applies save data (already parsed). Versions are checked/migrated BEFORE
## any state mutation, then the state is rebuilt from defaults and overlaid
## section by section (a broken section degrades to defaults with a warning,
## the rest still loads). Finishes by resuming the saved dialogue position.
func apply(data: Dictionary) -> Error:
	var version := int(data.get("save_version", -1))
	if version < 0:
		push_error("Narrative: save data has no valid save_version — refusing to load")
		return ERR_INVALID_DATA
	if version > NSVersion.SAVE_VERSION:
		push_error("Narrative: save_version %d is newer than this build supports (%d) — refusing to load" % [version, NSVersion.SAVE_VERSION])
		return ERR_INVALID_DATA

	var working := data.duplicate(true)
	while version < NSVersion.SAVE_VERSION:
		if not migrations.has(version):
			push_error("Narrative: missing save migration step %d -> %d — refusing to load" % [version, version + 1])
			return ERR_INVALID_DATA
		var migrated: Variant = (migrations[version] as Callable).call(working)
		if typeof(migrated) != TYPE_DICTIONARY:
			push_error("Narrative: save migration step %d returned invalid data — refusing to load" % version)
			return ERR_INVALID_DATA
		working = migrated
		version += 1
		working["save_version"] = version

	# --- from here on we mutate runtime state ---
	if _runner != null and _runner.is_dialogue_running():
		_runner.end_dialogue()
	_state.setup_from_database(_database)

	_localization.set_language(str(working.get("language", _localization.get_language())))

	var variables := _section(working, "variables")
	for variable_id: String in variables:
		var result := _state.set_value(variable_id, variables[variable_id])
		if not result.ok:
			push_warning("Narrative: save load — %s (value dropped)" % str(result.error))

	var quests := _section(working, "quests")
	for quest_id: String in quests:
		var entry: Variant = quests[quest_id]
		if typeof(entry) != TYPE_DICTIONARY or not VALID_QUEST_STATES.has(str((entry as Dictionary).get("state", ""))):
			push_warning("Narrative: save load — invalid quest entry '%s' dropped" % quest_id)
			continue
		if _database.get_quest(quest_id) == null:
			push_warning("Narrative: save load — quest '%s' is not in the database (kept as raw state)" % quest_id)
		_state.quest_states[quest_id] = _sanitize_quest_entry(quest_id, entry)

	var dialogue := _section(working, "dialogue")
	var seen := _subsection(dialogue, "seen_nodes")
	for dialogue_id: String in seen:
		if typeof(seen[dialogue_id]) == TYPE_ARRAY:
			for node_id in seen[dialogue_id]:
				_state.mark_seen(dialogue_id, str(node_id))
	if typeof(dialogue.get("history")) == TYPE_ARRAY:
		for item in dialogue.history:
			if typeof(item) == TYPE_DICTIONARY and item.has("d") and item.has("n"):
				_state.history.append({"d": str(item.d), "n": str(item.n), "t": int(item.get("t", 0))})
		while _state.history.size() > _state.history_limit:
			_state.history.pop_front()
	var current: Variant = dialogue.get("current")
	if typeof(current) == TYPE_DICTIONARY:
		_state.current_dialogue = {
			"dialogue_id": str(current.get("dialogue_id", "")),
			"node_id": str(current.get("node_id", "")),
			"phase": str(current.get("phase", "at_line")),
		}

	_state.custom_data = _section(working, "custom").duplicate(true)

	if _runner != null:
		_runner.try_resume()
	return OK


func _sanitize_quest_entry(quest_id: String, entry: Dictionary) -> Dictionary:
	var quest := _database.get_quest(quest_id)
	var objectives_raw: Variant = entry.get("objectives", {})
	var objectives_in: Dictionary = objectives_raw if typeof(objectives_raw) == TYPE_DICTIONARY else {}
	var objectives := {}
	for objective_id: String in objectives_in:
		var raw: Variant = objectives_in[objective_id]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var count := int((raw as Dictionary).get("count", 0))
		if quest != null:
			var objective := quest.get_objective_by_id(objective_id)
			if objective != null:
				count = clampi(count, 0, objective.target_count)
				objectives[objective_id] = {"count": count, "completed": count >= objective.target_count}
				continue
		objectives[objective_id] = {"count": maxi(count, 0), "completed": bool((raw as Dictionary).get("completed", false))}
	return {
		"state": str(entry.state),
		"tracked": bool(entry.get("tracked", false)),
		"objectives": objectives,
		"completions": maxi(int(entry.get("completions", 0)), 0),
	}


func _section(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		push_warning("Narrative: save load — section '%s' has the wrong type, using defaults" % key)
		return {}
	return value


func _subsection(data: Dictionary, key: String) -> Dictionary:
	return _section(data, key)
