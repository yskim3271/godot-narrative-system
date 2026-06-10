extends RefCounted
## Built-in DSL function library.
##
## An instance of this class is created per context; the function registry's
## Callables keep it alive. The context itself is held through a WeakRef to
## avoid a RefCounted reference cycle (context -> evaluator -> registry ->
## callables -> this object -> context).

var _ref: WeakRef


func install(context) -> void:
	_ref = weakref(context)
	var reg = context.evaluator.functions
	reg.register("str", fn_str)
	reg.register("has_seen", fn_has_seen)
	reg.register("quest_state", fn_quest_state)
	reg.register("is_quest_active", fn_is_quest_active)
	reg.register("is_quest_completed", fn_is_quest_completed)
	reg.register("is_quest_failed", fn_is_quest_failed)
	reg.register("start_quest", fn_start_quest)
	reg.register("complete_quest", fn_complete_quest)
	reg.register("fail_quest", fn_fail_quest)
	reg.register("update_objective", fn_update_objective)
	reg.register("set_expression", fn_set_expression)
	reg.register("alert", fn_alert)


func fn_str(value: Variant) -> String:
	return str(value)


func fn_has_seen(dialogue_id: String, node_id := "") -> bool:
	var ctx = _ctx()
	return ctx != null and ctx.state.has_seen(dialogue_id, node_id)


func fn_quest_state(quest_id: String) -> String:
	var quests = _quests()
	if quests == null:
		return "inactive"
	return quests.get_quest_state(quest_id)


func fn_is_quest_active(quest_id: String) -> bool:
	return fn_quest_state(quest_id) == "active"


func fn_is_quest_completed(quest_id: String) -> bool:
	return fn_quest_state(quest_id) == "completed"


func fn_is_quest_failed(quest_id: String) -> bool:
	return fn_quest_state(quest_id) == "failed"


func fn_start_quest(quest_id: String) -> bool:
	var quests = _quests("start_quest")
	return quests != null and quests.start_quest(quest_id)


func fn_complete_quest(quest_id: String) -> bool:
	var quests = _quests("complete_quest")
	return quests != null and quests.complete_quest(quest_id)


func fn_fail_quest(quest_id: String) -> bool:
	var quests = _quests("fail_quest")
	return quests != null and quests.fail_quest(quest_id)


func fn_update_objective(quest_id: String, objective_id: String, delta := 1.0) -> bool:
	var quests = _quests("update_objective")
	return quests != null and quests.update_objective(quest_id, objective_id, int(delta))


func fn_set_expression(character_id: String, expression: String) -> void:
	var ctx = _ctx()
	if ctx != null and ctx.runner != null:
		ctx.runner.notify_expression(character_id, expression)


func fn_alert(text_or_key: String) -> void:
	var ctx = _ctx()
	if ctx != null:
		ctx.request_alert(text_or_key)


func _ctx():
	return _ref.get_ref() if _ref != null else null


func _quests(api_name := ""):
	var ctx = _ctx()
	if ctx == null:
		return null
	if ctx.quests == null and api_name != "":
		push_error("Narrative DSL: %s() called but the quest manager is not available" % api_name)
	return ctx.quests
