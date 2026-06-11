@tool
class_name NarrativeQuestManager
extends RefCounted
## Quest lifecycle: inactive -> active -> completed | failed
## (-> back to inactive via abandon_quest; repeatable quests may also restart
## from completed/failed).
##
## All runtime quest state lives in NarrativeState.quest_states
## (copy-on-first-touch from the quest resources' initial values) — quest
## resources are NEVER mutated. A quest absent from quest_states is
## "inactive"; an abandoned quest with a completion history keeps an
## explicit {"state": "inactive"} entry so its completion count survives.
## Completion is explicit: objectives auto-complete at their target count
## (or when their auto_complete_condition turns true), but the quest itself
## completes only via complete_quest() (which requires all objectives done
## unless force = true).

signal quest_updated(quest_id: String)
## Emitted when one objective crosses into completed — via update_objective()
## reaching target_count or an auto_complete_condition turning true. (Not
## emitted for objectives that already start completed via initial_count.)
signal objective_completed(quest_id: String, objective_id: String)

const Evaluator := preload("dsl/evaluator.gd")
const STATES: PackedStringArray = ["inactive", "active", "completed", "failed"]
const MAX_ACTION_DEPTH := 8

var _database: NarrativeDatabase
var _state: NarrativeState
var _evaluator: Evaluator
var _localization: NarrativeLocalizationManager
var _action_depth := 0
var _warned: Dictionary = {}


func setup(
	database: NarrativeDatabase,
	state: NarrativeState,
	evaluator: Evaluator,
	localization: NarrativeLocalizationManager,
) -> void:
	_database = database
	_state = state
	_evaluator = evaluator
	_localization = localization
	# Objective auto_complete_conditions react to variable changes. The method
	# Callable holds this manager weakly (RefCounted method Callables do not
	# add a reference), so this never forms a cycle with the context graph.
	state.variable_changed.connect(_on_variable_changed)


# --- lifecycle ---


## Starts a quest. Fails (with a reason) when unknown, when not startable
## (inactive — or completed/failed for repeatable quests), or when
## prerequisites are not completed. Restarting a repeatable quest resets
## objective progress but keeps its completion count.
func start_quest(quest_id: String) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		push_error("Narrative: start_quest — unknown quest id '%s'" % quest_id)
		return false
	var current := get_quest_state(quest_id)
	var repeat_restart := quest.repeatable and current in ["completed", "failed"]
	if current != "inactive" and not repeat_restart:
		push_warning("Narrative: start_quest('%s') ignored — quest is already %s%s" % [
			quest_id, current,
			"" if quest.repeatable else " (set repeatable to allow restarts)",
		])
		return false
	for prerequisite in quest.prerequisites:
		if get_quest_state(prerequisite) != "completed":
			push_warning("Narrative: start_quest('%s') blocked — prerequisite '%s' is not completed" % [quest_id, prerequisite])
			return false
	var objectives := {}
	for objective in quest.objectives:
		if objective == null:
			continue
		var count := clampi(objective.initial_count, 0, objective.target_count)
		objectives[objective.id] = {"count": count, "completed": count >= objective.target_count}
	_state.quest_states[quest_id] = {
		"state": "active",
		"tracked": quest.auto_track,
		"objectives": objectives,
		"completions": get_times_completed(quest_id),
	}
	quest_updated.emit(quest_id)
	_apply_auto_completion(quest_id)  # conditions may already hold at start
	return true


## Completes an active quest and runs its reward actions. Requires all
## objectives completed unless force = true.
func complete_quest(quest_id: String, force := false) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		push_error("Narrative: complete_quest — unknown quest id '%s'" % quest_id)
		return false
	if get_quest_state(quest_id) != "active":
		push_warning("Narrative: complete_quest('%s') ignored — quest is %s" % [quest_id, get_quest_state(quest_id)])
		return false
	if not force and not are_all_objectives_completed(quest_id):
		push_warning("Narrative: complete_quest('%s') refused — objectives incomplete (pass force = true to override)" % quest_id)
		return false
	var entry: Dictionary = _state.quest_states[quest_id]
	entry.state = "completed"
	entry.completions = int(entry.get("completions", 0)) + 1
	quest_updated.emit(quest_id)
	if quest.rewards.strip_edges() != "":
		_action_depth += 1
		if _action_depth > MAX_ACTION_DEPTH:
			push_error("Narrative: quest reward recursion exceeded depth %d at '%s' — rewards skipped" % [MAX_ACTION_DEPTH, quest_id])
		else:
			_evaluator.run_actions(quest.rewards, "quest '%s' rewards" % quest_id)
		_action_depth -= 1
	return true


## Fails an active quest.
func fail_quest(quest_id: String) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		push_error("Narrative: fail_quest — unknown quest id '%s'" % quest_id)
		return false
	if get_quest_state(quest_id) != "active":
		push_warning("Narrative: fail_quest('%s') ignored — quest is %s" % [quest_id, get_quest_state(quest_id)])
		return false
	_state.quest_states[quest_id].state = "failed"
	quest_updated.emit(quest_id)
	return true


## Abandons an ACTIVE quest: it becomes "inactive" again (objective progress
## is discarded) and can be started afresh. The completion count of a
## previously completed repeatable quest survives.
func abandon_quest(quest_id: String) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		push_error("Narrative: abandon_quest — unknown quest id '%s'" % quest_id)
		return false
	if get_quest_state(quest_id) != "active":
		push_warning("Narrative: abandon_quest('%s') ignored — quest is %s" % [quest_id, get_quest_state(quest_id)])
		return false
	var completions := get_times_completed(quest_id)
	if completions > 0:
		# Keep an explicit inactive entry so the completion history persists
		# (and survives saves).
		_state.quest_states[quest_id] = {
			"state": "inactive",
			"tracked": false,
			"objectives": {},
			"completions": completions,
		}
	else:
		_state.quest_states.erase(quest_id)
	quest_updated.emit(quest_id)
	return true


## Adds delta to an objective counter (clamped to [0, target_count]).
## The objective's completed flag always reflects count >= target_count.
func update_objective(quest_id: String, objective_id: String, delta := 1) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		push_error("Narrative: update_objective — unknown quest id '%s'" % quest_id)
		return false
	var objective := quest.get_objective_by_id(objective_id)
	if objective == null:
		push_error("Narrative: update_objective — quest '%s' has no objective '%s'" % [quest_id, objective_id])
		return false
	if get_quest_state(quest_id) != "active":
		push_warning("Narrative: update_objective('%s', '%s') ignored — quest is %s" % [quest_id, objective_id, get_quest_state(quest_id)])
		return false
	var entry: Dictionary = _state.quest_states[quest_id]
	if not entry.objectives.has(objective_id):
		# Objective added to the database after this quest started: adopt it.
		entry.objectives[objective_id] = {"count": 0, "completed": false}
	var progress: Dictionary = entry.objectives[objective_id]
	var new_count := clampi(int(progress.count) + delta, 0, objective.target_count)
	if new_count == int(progress.count):
		return true
	var was_completed := bool(progress.completed)
	progress.count = new_count
	progress.completed = new_count >= objective.target_count
	if bool(progress.completed) and not was_completed:
		objective_completed.emit(quest_id, objective_id)
	quest_updated.emit(quest_id)
	return true


## Marks/unmarks a quest for the QuestTracker HUD.
func set_tracked(quest_id: String, tracked: bool) -> bool:
	if not _state.quest_states.has(quest_id):
		push_warning("Narrative: set_tracked('%s') ignored — quest was never started" % quest_id)
		return false
	if bool(_state.quest_states[quest_id].tracked) == tracked:
		return true
	_state.quest_states[quest_id].tracked = tracked
	quest_updated.emit(quest_id)
	return true


# --- queries ---


## "inactive" | "active" | "completed" | "failed". Unknown ids warn once
## and report "inactive".
func get_quest_state(quest_id: String) -> String:
	var entry: Variant = _state.quest_states.get(quest_id)
	if entry == null:
		if _database.get_quest(quest_id) == null and not _warned.has(quest_id):
			_warned[quest_id] = true
			push_warning("Narrative: quest id '%s' does not exist in the database" % quest_id)
		return "inactive"
	return str(entry.state)


func is_quest_active(quest_id: String) -> bool:
	return get_quest_state(quest_id) == "active"


func is_quest_completed(quest_id: String) -> bool:
	return get_quest_state(quest_id) == "completed"


func is_quest_failed(quest_id: String) -> bool:
	return get_quest_state(quest_id) == "failed"


func is_tracked(quest_id: String) -> bool:
	var entry: Variant = _state.quest_states.get(quest_id)
	return entry != null and bool(entry.tracked) and str(entry.state) == "active"


## Quest ids in the given state, sorted. "inactive" returns database quests
## that were never started plus abandoned ones.
func get_quests_in_state(state: String) -> Array[String]:
	var result: Array[String] = []
	if state == "inactive":
		for quest in _database.quests:
			if quest != null and quest.id != "" and get_quest_state(quest.id) == "inactive":
				result.append(quest.id)
	else:
		for quest_id: String in _state.quest_states:
			if str(_state.quest_states[quest_id].state) == state:
				result.append(quest_id)
	result.sort()
	return result


## How many times the quest has been completed (counts every completion of a
## repeatable quest; survives abandoning and restarting).
func get_times_completed(quest_id: String) -> int:
	var entry: Variant = _state.quest_states.get(quest_id)
	if entry == null:
		return 0
	return maxi(int(entry.get("completions", 0)), 0)


## The quest's authoring category ("" for unknown quests or none).
func get_quest_category(quest_id: String) -> String:
	var quest := _database.get_quest(quest_id)
	return quest.category if quest != null else ""


## All distinct non-empty categories in the database, sorted.
func get_categories() -> Array[String]:
	var found := {}
	for quest in _database.quests:
		if quest != null and quest.category != "":
			found[quest.category] = true
	var result: Array[String] = []
	for category: String in found:
		result.append(category)
	result.sort()
	return result


## Quest ids in a category, sorted; optionally filtered to one state.
func get_quests_in_category(category: String, state := "") -> Array[String]:
	var result: Array[String] = []
	for quest in _database.quests:
		if quest == null or quest.id == "" or quest.category != category:
			continue
		if state != "" and get_quest_state(quest.id) != state:
			continue
		result.append(quest.id)
	result.sort()
	return result


## Active quests marked for the tracker HUD, sorted.
func get_tracked_quests() -> Array[String]:
	var result: Array[String] = []
	for quest_id: String in _state.quest_states:
		var entry: Dictionary = _state.quest_states[quest_id]
		if str(entry.state) == "active" and bool(entry.tracked):
			result.append(quest_id)
	result.sort()
	return result


## Current progress count of one objective (initial value when the quest
## has not started, 0 for unknown ids).
func get_objective_count(quest_id: String, objective_id: String) -> int:
	var entry: Variant = _state.quest_states.get(quest_id)
	if entry != null and entry.objectives.has(objective_id):
		return int(entry.objectives[objective_id].count)
	var quest := _database.get_quest(quest_id)
	if quest != null:
		var objective := quest.get_objective_by_id(objective_id)
		if objective != null:
			return clampi(objective.initial_count, 0, objective.target_count)
	return 0


func are_all_objectives_completed(quest_id: String) -> bool:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		return false
	var entry: Variant = _state.quest_states.get(quest_id)
	for objective in quest.objectives:
		if objective == null:
			continue
		if entry == null:
			return false
		var progress: Variant = entry.objectives.get(objective.id)
		if progress == null or not bool(progress.completed):
			return false
	return true


# --- objective auto-completion ---


func _on_variable_changed(_variable_id: String, _value: Variant) -> void:
	recheck_auto_objectives()


## Re-evaluates the auto_complete_conditions of every active quest. Runs
## automatically on quest start and on every variable change; call it
## manually when an external condition source changed (e.g. after
## registering new DSL functions or mutating game state the conditions read).
func recheck_auto_objectives() -> void:
	for quest_id: String in _state.quest_states.keys():
		if str(_state.quest_states[quest_id].state) == "active":
			_apply_auto_completion(quest_id)


func _apply_auto_completion(quest_id: String) -> void:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		return
	var entry: Dictionary = _state.quest_states[quest_id]
	var changed := false
	for objective in quest.objectives:
		if objective == null or objective.auto_complete_condition.strip_edges() == "":
			continue
		if not entry.objectives.has(objective.id):
			# Objective added to the database after this quest started: adopt it.
			entry.objectives[objective.id] = {"count": 0, "completed": false}
		var progress: Dictionary = entry.objectives[objective.id]
		if bool(progress.completed):
			continue
		if _evaluator.eval_condition(objective.auto_complete_condition,
				"quest '%s' objective '%s' auto-complete" % [quest_id, objective.id]):
			progress.count = objective.target_count
			progress.completed = true
			changed = true
			objective_completed.emit(quest_id, objective.id)
	if changed:
		quest_updated.emit(quest_id)


# --- presentation helpers (localized, used by quest UIs) ---


func get_quest_title(quest_id: String) -> String:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		return quest_id
	var inline := quest.title if quest.title != "" else quest.id
	return _localization.resolve(quest.title_key, NarrativeLocalizationManager.quest_title_key(quest_id), inline)


func get_quest_description(quest_id: String) -> String:
	var quest := _database.get_quest(quest_id)
	if quest == null:
		return ""
	return _localization.resolve(quest.description_key, NarrativeLocalizationManager.quest_description_key(quest_id), quest.description)


## Authored-order objective progress:
## [{id, text, count, target, completed}, ...]
func get_objectives_progress(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest := _database.get_quest(quest_id)
	if quest == null:
		return result
	var entry: Variant = _state.quest_states.get(quest_id)
	for objective in quest.objectives:
		if objective == null:
			continue
		var count := clampi(objective.initial_count, 0, objective.target_count)
		var completed := count >= objective.target_count
		if entry != null and entry.objectives.has(objective.id):
			count = int(entry.objectives[objective.id].count)
			completed = bool(entry.objectives[objective.id].completed)
		result.append({
			"id": objective.id,
			"text": _localization.resolve(
				objective.description_key,
				NarrativeLocalizationManager.objective_key(quest_id, objective.id),
				objective.description,
			),
			"count": count,
			"target": objective.target_count,
			"completed": completed,
		})
	return result
