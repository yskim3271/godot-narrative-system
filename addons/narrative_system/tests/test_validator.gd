extends "res://addons/narrative_system/tests/harness/test_case.gd"
## NarrativeValidator: every check class, plus the clean-database guarantee.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")


func _validate(db: NarrativeDatabase) -> Array[Dictionary]:
	return NarrativeValidator.new().validate(db)


func _codes(issues: Array[Dictionary], severity := "") -> Array[String]:
	var result: Array[String] = []
	for issue in issues:
		if severity == "" or issue.severity == severity:
			result.append(str(issue.code))
	return result


func _has_issue(issues: Array[Dictionary], code: String, where_contains := "") -> bool:
	for issue in issues:
		if issue.code == code and (where_contains == "" or str(issue.where).contains(where_contains)):
			return true
	return false


func test_clean_database_has_zero_issues() -> void:
	var issues := _validate(DbFactory.clean())
	for issue in issues:
		fail("unexpected issue: " + NarrativeValidator.format_issue(issue))
	assert_eq(issues.size(), 0)


func test_missing_start_node() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].start_node_id = ""
	assert_true(_has_issue(_validate(db), "missing_start_node"))
	db.dialogues[0].start_node_id = "ghost"
	assert_true(_has_issue(_validate(db), "missing_start_node"))


func test_broken_next_and_choice_targets() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].next_node_id = "nowhere"
	db.dialogues[0].nodes[1].choices[0].target_node_id = "nowhere_else"
	var issues := _validate(db)
	assert_true(_has_issue(issues, "broken_link", "node 'h1'"))
	assert_true(_has_issue(issues, "broken_link", "choice 'more'"))


func test_unreachable_node_warning() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes.append(DbFactory.make_node("island", {"text": "isolated"}))
	var issues := _validate(db)
	assert_true(_has_issue(issues, "unreachable_node", "hello"))
	assert_eq(NarrativeValidator.count_severity(issues, "error"), 0, "unreachable is a warning, not an error")


func test_unknown_ids_in_fields_and_dsl() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].speaker_id = "ghost_speaker"
	db.dialogues[0].nodes[0].actions = "start_quest(\"ghost_quest\")\nupdate_objective(\"intro\", \"ghost_obj\")"
	db.dialogues[0].nodes[1].conditions = "has_seen(\"ghost_dlg\") or has_seen(\"hello\", \"ghost_node\")"
	var issues := _validate(db)
	assert_true(_has_issue(issues, "unknown_character_id", "node 'h1'"))
	assert_true(_has_issue(issues, "unknown_quest_id"))
	assert_true(_has_issue(issues, "unknown_objective_id"))
	assert_true(_has_issue(issues, "unknown_dialogue_id"))
	assert_true(_has_issue(issues, "unknown_node_id"))


func test_duplicate_ids() -> void:
	var db := DbFactory.clean()
	db.quests.append(DbFactory.make_quest("intro", {}))
	db.dialogues[0].nodes.append(DbFactory.make_node("h1", {"text": "imposter"}))
	var issues := _validate(db)
	assert_true(_has_issue(issues, "duplicate_id", "quest"))
	assert_true(_has_issue(issues, "duplicate_id", "dialogue 'hello'"))


func test_shared_resource_instance_detected() -> void:
	var db := DbFactory.clean()
	var shared := db.dialogues[0].nodes[2]
	db.dialogues.append(DbFactory.make_dialogue("other", "h3", [shared]))
	assert_true(_has_issue(_validate(db), "shared_resource_instance"))


func test_dsl_parse_error_reported_with_location() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].conditions = "gold >= "
	var issues := _validate(db)
	assert_true(_has_issue(issues, "dsl_parse_error", "node 'h1' > conditions"))
	var found := false
	for issue in issues:
		if issue.code == "dsl_parse_error":
			found = issue.message.contains("parse error at")
	assert_true(found, "parse errors carry a position")


func test_missing_localization_key_warning() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].localized_text_key = "nope.key"
	db.quests[0].title_key = "also.nope"
	var issues := _validate(db)
	assert_true(_has_issue(issues, "missing_localization_key", "node 'h1'"))
	assert_true(_has_issue(issues, "missing_localization_key", "quest 'intro'"))


func test_unknown_function_and_declared_external() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].conditions = "has_item(\"sword\")"
	assert_true(_has_issue(_validate(db), "unknown_function"))
	db.settings = NarrativeSettings.new()
	db.settings.declared_external_functions = PackedStringArray(["has_item"])
	assert_false(_has_issue(_validate(db), "unknown_function"), "declared external functions are accepted")


func test_undeclared_variable_warnings() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].conditions = "mystery_var == null"
	db.dialogues[0].nodes[0].actions = "another_mystery = 1"
	var issues := _validate(db)
	assert_true(_has_issue(issues, "undeclared_variable", "conditions"))
	assert_true(_has_issue(issues, "undeclared_variable", "actions"))
	assert_eq(NarrativeValidator.count_severity(issues, "error"), 0)


func test_id_charset_warning() -> void:
	var db := DbFactory.clean()
	db.characters.append(DbFactory.make_character("bad id!", "Bad"))
	assert_true(_has_issue(_validate(db), "id_charset"))


func test_standard_fixture_reports_known_smells() -> void:
	# The runner-test fixture deliberately contains broken/cyclic dialogues;
	# the validator must see them.
	var issues := _validate(DbFactory.standard())
	assert_true(_has_issue(issues, "broken_link", "dialogue 'broken'"), "missing next target")
	assert_true(_has_issue(issues, "suspicious_loop", "dialogue 'cycle'"), "condition-skip cycle")
	assert_true(_has_issue(issues, "missing_localization_key", "dialogue 'loctest'"))


func test_markup_unknown_variable_warning() -> void:
	var db := DbFactory.clean()
	db.dialogues[0].nodes[0].text = "Have [var=gold] and [var=ghost_var]"
	db.dialogues[0].nodes[1].choices[0].text = "Pay [var=other_ghost]"
	var issues := _validate(db)
	assert_true(_has_issue(issues, "markup_unknown_variable", "node 'h1' > text"))
	assert_true(_has_issue(issues, "markup_unknown_variable", "choice 'more'"))
	assert_eq(NarrativeValidator.count_severity(issues, "error"), 0, "markup issues are warnings")
	# declared variables (and malformed tags) produce no markup issues
	db.dialogues[0].nodes[0].text = "Have [var=gold] and [var=broken"
	db.dialogues[0].nodes[1].choices[0].text = "ok"
	assert_false(_has_issue(_validate(db), "markup_unknown_variable"))


func test_parse_where_formats() -> void:
	var ref := NarrativeValidator.parse_where("dialogue 'd1' > node 'n1' > choice 'c1' > text")
	assert_eq(ref.category, "dialogue")
	assert_eq(ref.id, "d1")
	assert_eq(ref.node, "n1")
	assert_eq(ref.choice, "c1")
	assert_eq(ref.field, "text")
	ref = NarrativeValidator.parse_where("quest 'q' > objective 'o'")
	assert_eq(ref.category, "quest")
	assert_eq(ref.objective, "o")
	ref = NarrativeValidator.parse_where("quest 'q' > rewards")
	assert_eq(ref.field, "rewards")
	ref = NarrativeValidator.parse_where("character 'guard'")
	assert_eq(ref.category, "character")
	ref = NarrativeValidator.parse_where("variables[3]")
	assert_eq(ref.category, "variable")
	assert_eq(int(ref.index), 3)
	assert_eq(NarrativeValidator.parse_where("database").category, "database")
	assert_eq(NarrativeValidator.parse_where(""), {})
	assert_eq(NarrativeValidator.parse_where("garbage segment"), {})


func test_parse_where_roundtrip_on_real_issues() -> void:
	# Every issue the validator emits on the (deliberately broken) standard
	# fixture must parse back into a resolvable reference.
	var db := DbFactory.standard()
	var issues := _validate(db)
	assert_true(issues.size() > 0)
	for issue in issues:
		var ref := NarrativeValidator.parse_where(str(issue.where))
		assert_false(ref.is_empty(), "unparseable where: '%s'" % str(issue.where))
		var resolved := NarrativeValidator.resolve_reference(db, ref)
		assert_true(
			resolved.resource != null or ref.has("index") or str(ref.get("category")) == "database",
			"unresolvable where: '%s'" % str(issue.where)
		)


func test_resolve_reference_targets() -> void:
	var db := DbFactory.standard()
	var node_ref := NarrativeValidator.resolve_reference(db,
		{"category": "dialogue", "id": "branch", "node": "q"})
	assert_eq(node_ref.resource, db.get_dialogue("branch").get_node_by_id("q"))
	assert_eq(node_ref.dialogue_id, "branch")
	assert_eq(node_ref.node_id, "q")
	var choice_ref := NarrativeValidator.resolve_reference(db,
		{"category": "dialogue", "id": "branch", "node": "q", "choice": "stay"})
	assert_eq(choice_ref.resource, db.get_dialogue("branch").get_node_by_id("q").choices[0])
	assert_eq(choice_ref.node_id, "q", "graph focus still points at the owning node")
	var objective_ref := NarrativeValidator.resolve_reference(db,
		{"category": "quest", "id": "rats", "objective": "kill_rats"})
	assert_eq(objective_ref.resource, db.get_quest("rats").objectives[0])
	var missing := NarrativeValidator.resolve_reference(db, {"category": "dialogue", "id": "ghost"})
	assert_null(missing.resource)
	assert_eq(NarrativeValidator.resolve_reference(db, {}).resource, null)
