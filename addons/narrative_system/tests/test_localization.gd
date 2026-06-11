extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Localization: lookup chain, runtime switching, missing keys, CSV roundtrip.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")
const CsvExporter := preload("res://addons/narrative_system/import_export/csv_exporter.gd")
const CsvImporter := preload("res://addons/narrative_system/import_export/csv_importer.gd")

var ctx: NarrativeContext


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard())


func after_each() -> void:
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.localization)
	disconnect_all_signals(ctx)
	ctx = null
	for path in ["user://t_loc.csv", "user://t_loc_bom.csv"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_lookup_current_language_and_fallback() -> void:
	assert_eq(ctx.localization.get_language(), "en")
	assert_eq(ctx.localization.lookup("greet.key"), "Hello")
	ctx.localization.set_language("ko")
	assert_eq(ctx.localization.lookup("greet.key"), "안녕하세요")
	# key that only exists in ko, while current is ja -> falls back to en -> missing -> ""
	ctx.localization.set_language("ja")
	assert_eq(ctx.localization.lookup("greet.key"), "Hello", "ja falls back to en")
	assert_eq(ctx.localization.lookup("only.korean"), "", "no ja, no en entry -> empty")


func test_three_step_resolution_in_dialogue() -> void:
	# inline text (en has no convention entry)
	ctx.runner.start_dialogue("linear")
	assert_eq(ctx.runner.get_current_line_text(), "first")
	ctx.runner.end_dialogue()
	# convention key wins in ko
	ctx.localization.set_language("ko")
	ctx.runner.start_dialogue("linear")
	assert_eq(ctx.runner.get_current_line_text(), "첫 번째")
	ctx.runner.end_dialogue()
	# explicit key wins over inline
	ctx.runner.start_dialogue("loctest")
	assert_eq(ctx.runner.get_current_line_text(), "안녕하세요")
	ctx.runner.advance()
	assert_eq(ctx.runner.get_current_line_text(), "fallback line", "missing explicit key falls back to inline")
	ctx.runner.end_dialogue()


func test_missing_explicit_keys_are_collected() -> void:
	ctx.runner.start_dialogue("loctest")
	ctx.runner.advance()  # L2 has localized_text_key = "missing.key"
	assert_contains(ctx.localization.missing_keys(), "missing.key")
	ctx.runner.end_dialogue()
	ctx.localization.clear_missing_keys()
	assert_eq(ctx.localization.missing_keys().size(), 0)
	# collection can be disabled via settings
	var db := DbFactory.standard()
	db.settings = NarrativeSettings.new()
	db.settings.collect_missing_keys = false
	var quiet := NarrativeContext.create(db)
	quiet.runner.start_dialogue("loctest")
	quiet.runner.advance()
	assert_eq(quiet.localization.missing_keys().size(), 0)


func test_runtime_language_switch_represents_current_line() -> void:
	ctx.runner.start_dialogue("linear")
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx.runner, ["line_presented"])
	rec.watch(ctx.localization, ["language_changed"])
	ctx.localization.set_language("ko")
	assert_eq(rec.count("language_changed"), 1)
	assert_eq(rec.count("line_presented"), 1, "current line re-presented on language change")
	assert_eq(rec.args_of("line_presented"), ["guard", "첫 번째"])
	assert_eq(ctx.runner.get_character_display_name("guard"), "경비병", "convention char name key")
	ctx.localization.set_language("ko")
	assert_eq(rec.count("language_changed"), 1, "same language is a no-op")


func test_inline_preferred_over_fallback_locale() -> void:
	# Database authored in Korean (default ko, fallback en); the table only
	# has an ENGLISH entry for n2. Korean players must see the Korean inline
	# text — never the fallback language.
	var db := DbFactory.standard()
	db.settings = NarrativeSettings.new()
	db.settings.default_language = "ko"
	db.settings.fallback_language = "en"
	db.localization_tables[0].set_text("dlg.linear.n2.text", "en", "second EN")
	var local_ctx := NarrativeContext.create(db)
	local_ctx.runner.start_dialogue("linear")
	local_ctx.runner.advance()  # n2
	assert_eq(local_ctx.runner.get_current_line_text(), "second", "ko player sees the ko inline, not the en table entry")
	local_ctx.localization.set_language("en")
	assert_eq(local_ctx.runner.get_current_line_text(), "second EN", "en player sees the en table entry")
	local_ctx.runner.end_dialogue()
	disconnect_all_signals(local_ctx.runner)


func test_quest_and_ui_convention_keys() -> void:
	ctx.localization.set_language("ko")
	assert_eq(ctx.quests.get_quest_title("rats"), "쥐 사냥")
	assert_eq(ctx.localization.text_or("ui.quest_log.title", "Quests"), "퀘스트")
	assert_eq(ctx.localization.text_or("ui.nonexistent", "Fallback"), "Fallback")
	assert_eq(ctx.localization.resolve_text_or_key("ui.alert.reward"), "보상!")
	assert_eq(ctx.localization.resolve_text_or_key("plain text"), "plain text")


func test_csv_roundtrip_korean() -> void:
	var table := DbFactory.make_loc_table()
	assert_eq(CsvExporter.export_table(table, "user://t_loc.csv"), OK)
	var imported := NarrativeLocalizationTable.new()
	var result := CsvImporter.import_into(imported, "user://t_loc.csv")
	assert_true(result.ok)
	assert_eq(result.locales, PackedStringArray(["en", "ko"]))
	assert_eq(imported.entries.size(), table.entries.size())
	assert_eq(imported.get_text("greet.key", "ko"), "안녕하세요")
	assert_eq(imported.get_text("ui.alert.reward", "en"), "Reward!")
	assert_eq(imported.get_text("only.korean", "ko"), "한국어만")
	assert_false(imported.has_text("only.korean", "en"), "empty cells must not create entries")


func test_csv_import_strips_bom_and_rejects_bad_header() -> void:
	var file := FileAccess.open("user://t_loc_bom.csv", FileAccess.WRITE)
	file.store_string(String.chr(0xFEFF) + "key,en,ko\nbom.test,\"Hi, there\",안녕\n")
	file.close()
	var table := NarrativeLocalizationTable.new()
	var result := CsvImporter.import_into(table, "user://t_loc_bom.csv")
	assert_true(result.ok)
	assert_eq(table.get_text("bom.test", "en"), "Hi, there", "quoted comma survives")
	assert_eq(table.get_text("bom.test", "ko"), "안녕")

	var bad := FileAccess.open("user://t_loc_bom.csv", FileAccess.WRITE)
	bad.store_string("note,en\nx,y\n")
	bad.close()
	var bad_result := CsvImporter.import_into(NarrativeLocalizationTable.new(), "user://t_loc_bom.csv")
	assert_false(bad_result.ok)
	assert_contains(bad_result.error, "invalid header")


func test_language_persists_through_save_load() -> void:
	ctx.localization.set_language("ko")
	assert_eq(ctx.save_manager.save_game("t_loc_save"), OK)
	var fresh := NarrativeContext.create(DbFactory.standard())
	assert_eq(fresh.localization.get_language(), "en")
	fresh.save_manager.load_game("t_loc_save")
	assert_eq(fresh.localization.get_language(), "ko")
	ctx.save_manager.delete_save("t_loc_save")
