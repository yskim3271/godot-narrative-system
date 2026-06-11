extends "res://addons/narrative_system/tests/harness/test_case.gd"
## localization_report.gd: translation coverage rules (default-language inline
## coverage, explicit/convention keys, skipping unauthored units, refs).

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const LocReport := preload("res://addons/narrative_system/editor/localization_report.gd")


func _row(report: Dictionary, where_contains: String) -> Dictionary:
	for row: Dictionary in report.rows:
		if str(row.where).contains(where_contains):
			return row
	return {}


func test_locales_and_summary_counts() -> void:
	var report := LocReport.build(DbFactory.standard())
	assert_eq(report.locales, PackedStringArray(["en", "ko"]))
	assert_eq(report.default_language, "en")
	assert_true(int(report.units) > 0)
	assert_eq(int(report.missing_by_locale.get("en", -1)), 0,
		"every unit has inline text or an en key — nothing missing in the default language")
	assert_true(int(report.missing_by_locale.get("ko", 0)) > 0)
	assert_eq(report.rows.size(), int(report.missing_by_locale.ko),
		"standard fixture rows are exactly the ko gaps")


func test_default_language_covered_by_inline_text() -> void:
	var report := LocReport.build(DbFactory.standard())
	# n1 has a ko convention-key entry AND inline en text -> fully covered.
	assert_eq(_row(report, "node 'n1' > text"), {})
	# n2 has inline en text only -> missing ko.
	var row := _row(report, "node 'n2' > text")
	assert_false(row.is_empty())
	assert_eq(row.missing, PackedStringArray(["ko"]))
	assert_eq(str(row.key), "dlg.linear.n2.text")


func test_explicit_key_units() -> void:
	var report := LocReport.build(DbFactory.standard())
	# L1 -> greet.key exists in en and ko: covered.
	assert_eq(_row(report, "node 'L1'"), {})
	# L2 -> explicit missing.key exists nowhere; inline covers en only.
	var row := _row(report, "node 'L2'")
	assert_eq(str(row.key), "missing.key")
	assert_eq(row.missing, PackedStringArray(["ko"]))


func test_character_quest_objective_units() -> void:
	var report := LocReport.build(DbFactory.standard())
	assert_eq(_row(report, "character 'guard'"), {}, "char.guard.name has ko, inline covers en")
	assert_false(_row(report, "character 'player'").is_empty())
	assert_eq(_row(report, "quest 'rats' > title"), {}, "quest.rats.title has ko")
	assert_false(_row(report, "quest 'intro' > title").is_empty())
	assert_false(_row(report, "quest 'rats' > description").is_empty())
	assert_false(_row(report, "objective 'kill_rats'").is_empty())


func test_key_only_unit_missing_default_language() -> void:
	var db := NarrativeDatabase.new()
	db.localization_tables = [DbFactory.make_loc_table()]
	db.dialogues = [DbFactory.make_dialogue("kd", "k1", [
		DbFactory.make_node("k1", {"text": "", "key": "only.korean"}),
	])]
	var report := LocReport.build(db)
	var row := _row(report, "node 'k1'")
	assert_eq(row.missing, PackedStringArray(["en"]),
		"key-only unit with no inline text is NOT covered in the default language")


func test_nothing_authored_is_skipped() -> void:
	var db := NarrativeDatabase.new()
	db.localization_tables = [DbFactory.make_loc_table()]
	db.dialogues = [DbFactory.make_dialogue("kd", "k1", [
		DbFactory.make_node("k1", {"text": ""}),
	])]
	var report := LocReport.build(db)
	assert_eq(int(report.units), 0, "empty text without any key is not a translatable unit")
	assert_eq(report.rows.size(), 0)


func test_row_refs_point_at_resources() -> void:
	var db := DbFactory.standard()
	var report := LocReport.build(db)
	var node_row := _row(report, "node 'n2' > text")
	assert_eq(str(node_row.ref.category), "dialogue")
	assert_eq(str(node_row.ref.id), "linear")
	assert_eq(str(node_row.ref.node), "n2")
	var choice_row := _row(report, "choice 'stay'")
	assert_false(choice_row.is_empty(), "choices without ko entries are units too")
	assert_eq(str(choice_row.ref.choice), "stay")
	# every ref must resolve through the shared validator resolver
	for row: Dictionary in report.rows:
		var resolved := NarrativeValidator.resolve_reference(db, row.ref)
		assert_not_null(resolved.resource, "unresolvable ref for: %s" % str(row.where))
