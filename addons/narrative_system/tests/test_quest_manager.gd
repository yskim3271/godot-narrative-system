extends "res://addons/narrative_system/tests/harness/test_case.gd"
## QuestManager: lifecycle, prerequisites, objectives, rewards, purity.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")

var ctx: NarrativeContext
var rec: RefCounted


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard())
	rec = SignalRecorder.new()
	rec.watch(ctx.quests, ["quest_updated"])


func after_each() -> void:
	disconnect_all_signals(ctx.quests)
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx)
	ctx = null


func test_start_quest_and_signal() -> void:
	assert_eq(ctx.quests.get_quest_state("rats"), "inactive")
	assert_true(ctx.quests.start_quest("rats"))
	assert_eq(ctx.quests.get_quest_state("rats"), "active")
	assert_true(ctx.quests.is_quest_active("rats"))
	assert_true(ctx.quests.is_tracked("rats"), "auto_track quests are tracked on start")
	assert_eq(rec.count("quest_updated"), 1)
	assert_eq(rec.args_of("quest_updated"), ["rats"])
	assert_false(ctx.quests.start_quest("rats"), "double start is rejected")


func test_prerequisites_block_start() -> void:
	assert_false(ctx.quests.start_quest("after"), "prerequisite 'intro' not completed")
	assert_eq(ctx.quests.get_quest_state("after"), "inactive")
	ctx.quests.start_quest("intro")
	ctx.quests.complete_quest("intro")
	assert_true(ctx.quests.start_quest("after"))


func test_objective_increment_clamp_and_completion_flag() -> void:
	ctx.quests.start_quest("rats")
	assert_true(ctx.quests.update_objective("rats", "kill_rats", 3))
	var progress := ctx.quests.get_objectives_progress("rats")[0]
	assert_eq(progress.count, 3)
	assert_false(bool(progress.completed))
	ctx.quests.update_objective("rats", "kill_rats", 10)
	progress = ctx.quests.get_objectives_progress("rats")[0]
	assert_eq(progress.count, 5, "count clamps to target_count")
	assert_true(bool(progress.completed))
	ctx.quests.update_objective("rats", "kill_rats", -2)
	progress = ctx.quests.get_objectives_progress("rats")[0]
	assert_eq(progress.count, 3)
	assert_false(bool(progress.completed), "completed reflects count >= target")
	assert_false(ctx.quests.are_all_objectives_completed("rats"))


func test_complete_requires_objectives_unless_forced() -> void:
	ctx.quests.start_quest("rats")
	assert_false(ctx.quests.complete_quest("rats"), "incomplete objectives refuse completion")
	assert_eq(ctx.quests.get_quest_state("rats"), "active")
	ctx.quests.update_objective("rats", "kill_rats", 5)
	assert_true(ctx.quests.complete_quest("rats"))
	assert_eq(ctx.quests.get_quest_state("rats"), "completed")
	assert_eq(ctx.state.get_value("gold"), 110, "reward actions ran (gold += 100)")


func test_force_complete_skips_objective_check() -> void:
	ctx.quests.start_quest("rats")
	assert_true(ctx.quests.complete_quest("rats", true))
	assert_eq(ctx.quests.get_quest_state("rats"), "completed")


func test_fail_quest_and_state_queries() -> void:
	ctx.quests.start_quest("rats")
	assert_true(ctx.quests.fail_quest("rats"))
	assert_true(ctx.quests.is_quest_failed("rats"))
	assert_false(ctx.quests.complete_quest("rats"), "failed quest cannot complete")
	assert_false(ctx.quests.fail_quest("rats"), "failed quest cannot fail again")
	assert_eq(ctx.quests.get_quests_in_state("failed"), ["rats"] as Array[String])


func test_unknown_ids_no_crash() -> void:
	assert_false(ctx.quests.start_quest("ghost"))
	assert_false(ctx.quests.complete_quest("ghost"))
	assert_false(ctx.quests.fail_quest("ghost"))
	assert_false(ctx.quests.update_objective("ghost", "x"))
	assert_false(ctx.quests.update_objective("rats", "ghost_objective"))
	assert_eq(ctx.quests.get_quest_state("ghost"), "inactive")
	assert_eq(rec.count("quest_updated"), 0)


func test_reward_chain_completes_other_quest() -> void:
	ctx.quests.start_quest("chain_a")
	ctx.quests.start_quest("chain_b")
	assert_true(ctx.quests.complete_quest("chain_a"))
	assert_true(ctx.quests.is_quest_completed("chain_b"), "chain_a's reward completed chain_b via DSL")


func test_quest_from_dialogue_actions() -> void:
	ctx.runner.start_dialogue("questgiver")
	assert_true(ctx.quests.is_quest_active("rats"), "node action started the quest")
	assert_true(ctx.runner.advance(), "g2's is_quest_active condition passes")
	assert_eq(ctx.runner.get_current_line_text(), "they await")
	ctx.runner.end_dialogue()


func test_tracked_toggle_and_lists() -> void:
	ctx.quests.start_quest("rats")
	ctx.quests.start_quest("untracked")
	assert_eq(ctx.quests.get_tracked_quests(), ["rats"] as Array[String])
	ctx.quests.set_tracked("untracked", true)
	assert_eq(ctx.quests.get_tracked_quests(), ["rats", "untracked"] as Array[String])
	ctx.quests.set_tracked("rats", false)
	assert_eq(ctx.quests.get_tracked_quests(), ["untracked"] as Array[String])
	assert_eq(ctx.quests.get_quests_in_state("active"), ["rats", "untracked"] as Array[String])
	assert_false(ctx.quests.set_tracked("never_started_quest", true))


func test_runtime_never_mutates_quest_resources() -> void:
	var quest := ctx.database.get_quest("rats")
	var objective := quest.objectives[0]
	var snapshot := {
		"title": quest.title,
		"rewards": quest.rewards,
		"initial": objective.initial_count,
		"target": objective.target_count,
	}
	ctx.quests.start_quest("rats")
	ctx.quests.update_objective("rats", "kill_rats", 5)
	ctx.quests.complete_quest("rats")
	assert_eq(quest.title, snapshot.title)
	assert_eq(quest.rewards, snapshot.rewards)
	assert_eq(objective.initial_count, snapshot.initial, "runtime progress must never touch the resource")
	assert_eq(objective.target_count, snapshot.target)
	assert_true(ctx.state.quest_states.has("rats"), "runtime state lives in NarrativeState")
