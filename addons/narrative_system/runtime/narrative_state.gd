class_name NarrativeState
extends RefCounted
## Single source of truth for all mutable narrative runtime state:
## variable values, seen nodes, history, quest runtime state, the current
## dialogue position and game-owned custom data.
##
## Resources are never mutated — everything mutable lives here, which is
## exactly what the SaveManager serializes.

signal variable_changed(variable_id: String, value: Variant)

var _declared: Dictionary = {}  # id -> NarrativeVariable
var _values: Dictionary = {}    # id -> Variant

## dialogue_id -> { node_id: true } (nodes whose line was actually presented)
var seen: Dictionary = {}
## Ring buffer of {d: dialogue_id, n: node_id, t: unix} entries.
var history: Array[Dictionary] = []
var history_limit := 200
var strict_variables := false

## quest_id -> {state: String, tracked: bool, objectives: {id: {count, completed}}}
## Managed exclusively by the QuestManager. Quests not present are "inactive".
var quest_states: Dictionary = {}

## {} when idle, else {dialogue_id, node_id, phase} (phase: "at_line"/"at_choices").
var current_dialogue: Dictionary = {}

## Game-owned JSON-safe data persisted through the same save file.
var custom_data: Dictionary = {}


## Full reset + (re)declaration of variables from the database.
func setup_from_database(database: NarrativeDatabase) -> void:
	var settings := database.get_settings()
	history_limit = settings.history_limit
	strict_variables = settings.strict_variables
	_declared.clear()
	_values.clear()
	seen.clear()
	history.clear()
	quest_states.clear()
	current_dialogue = {}
	custom_data = {}
	for variable in database.variables:
		if variable == null:
			continue
		if variable.id == "":
			push_error("NarrativeState: variable with empty id skipped")
			continue
		if _declared.has(variable.id):
			push_error("NarrativeState: duplicate variable id '%s' (first definition wins)" % variable.id)
			continue
		_declared[variable.id] = variable
		_values[variable.id] = variable.get_default()


# --- variables ---


func has_value(variable_id: String) -> bool:
	return _values.has(variable_id)


func is_declared(variable_id: String) -> bool:
	return _declared.has(variable_id)


## Current value, or null when the variable does not exist.
## (Callers decide how to report missing variables.)
func get_value(variable_id: String) -> Variant:
	return _values.get(variable_id)


## Sets a variable, coercing to the declared type. Returns
## {ok: bool, error?: String, warning?: String}; never pushes engine errors.
func set_value(variable_id: String, value: Variant) -> Dictionary:
	if variable_id == "":
		return {"ok": false, "error": "empty variable id"}
	var coerced := value
	var declared: NarrativeVariable = _declared.get(variable_id)
	var result := {"ok": true}
	if declared != null:
		var coercion := _coerce(declared.type, value)
		if not coercion.ok:
			return {
				"ok": false,
				"error": "cannot assign %s to %s variable '%s'" % [
					type_string(typeof(value)),
					NarrativeVariable.Type.keys()[declared.type],
					variable_id,
				],
			}
		coerced = coercion.value
	elif strict_variables:
		result["warning"] = "assignment to undeclared variable '%s'" % variable_id
	var changed: bool = not _values.has(variable_id) or not _same_value(_values[variable_id], coerced)
	_values[variable_id] = coerced
	if changed:
		variable_changed.emit(variable_id, coerced)
	return result


## Snapshot of all values (used by the SaveManager).
func variable_values() -> Dictionary:
	return _values.duplicate()


## Whether a variable should be written into save files.
func is_persistent(variable_id: String) -> bool:
	var declared: NarrativeVariable = _declared.get(variable_id)
	return declared == null or declared.persistent


func declared_type(variable_id: String) -> int:
	var declared: NarrativeVariable = _declared.get(variable_id)
	return declared.type if declared != null else -1


# --- seen nodes / history ---


func mark_seen(dialogue_id: String, node_id: String) -> void:
	if not seen.has(dialogue_id):
		seen[dialogue_id] = {}
	seen[dialogue_id][node_id] = true


## has_seen(dialogue_id) = any node of that dialogue was presented;
## has_seen(dialogue_id, node_id) = that specific node was presented.
func has_seen(dialogue_id: String, node_id := "") -> bool:
	if not seen.has(dialogue_id):
		return false
	if node_id == "":
		return true
	return seen[dialogue_id].has(node_id)


func append_history(dialogue_id: String, node_id: String) -> void:
	history.append({"d": dialogue_id, "n": node_id, "t": int(Time.get_unix_time_from_system())})
	while history.size() > history_limit:
		history.pop_front()


func _coerce(type: int, value: Variant) -> Dictionary:
	match type:
		NarrativeVariable.Type.BOOL:
			if typeof(value) == TYPE_BOOL:
				return {"ok": true, "value": value}
		NarrativeVariable.Type.INT:
			if typeof(value) == TYPE_INT:
				return {"ok": true, "value": value}
			if typeof(value) == TYPE_FLOAT:
				return {"ok": true, "value": int(value)}
		NarrativeVariable.Type.FLOAT:
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				return {"ok": true, "value": float(value)}
		NarrativeVariable.Type.STRING:
			if typeof(value) == TYPE_STRING:
				return {"ok": true, "value": value}
	return {"ok": false}


func _same_value(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
