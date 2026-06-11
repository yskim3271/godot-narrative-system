@tool
extends VBoxContainer
## Bottom-panel shell: database path bar + tabs (Database overview /
## Validation / Localization coverage / Preview) + CSV import/export.
## Built entirely in code; never touches the runtime autoload (loads the
## database itself from the project setting). The preview tab runs dialogues
## in a sandboxed context; validation/localization rows double-click-focus
## their resource (Inspector + main-screen graph via set_graph_editor).

const SETTING_DATABASE_PATH := "narrative_system/database_path"
const DatabaseEditor := preload("database_editor.gd")
const ValidationPanel := preload("validation_panel.gd")
const LocalizationPanel := preload("localization_panel.gd")
const PreviewPanel := preload("preview_panel.gd")
const CsvExporter := preload("../import_export/csv_exporter.gd")
const CsvImporter := preload("../import_export/csv_importer.gd")
const ScriptParser := preload("../import_export/dialogue_script_parser.gd")

var _db: NarrativeDatabase
var _path_edit: LineEdit
var _status: Label
var _tabs: TabContainer
var _overview: Tree
var _validation: VBoxContainer
var _localization: VBoxContainer
var _preview: VBoxContainer
var _file_dialog: EditorFileDialog
## Main-screen graph editor, injected by plugin.gd (null when headless).
var _graph_editor: Control


func _init() -> void:
	name = "NarrativePanel"
	custom_minimum_size = Vector2(0, 240)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var path_label := Label.new()
	path_label.text = "Database:"
	toolbar.add_child(path_label)

	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "res://narrative_database.tres"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.text_submitted.connect(func(_t: String) -> void: _load_database())
	toolbar.add_child(_path_edit)

	_add_button(toolbar, "Browse…", _browse_database)
	_add_button(toolbar, "Load", _load_database)
	toolbar.add_child(VSeparator.new())
	_add_button(toolbar, "Validate", _validate)
	_add_button(toolbar, "Export CSV", _export_csv)
	_add_button(toolbar, "Import CSV", _import_csv)
	_add_button(toolbar, "Import Script", _import_script)

	_status = Label.new()
	_status.text = ""
	_status.modulate = Color(1, 1, 1, 0.7)
	toolbar.add_child(_status)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)

	_overview = DatabaseEditor.new()
	_overview.name = "Database"
	_tabs.add_child(_overview)

	_validation = ValidationPanel.new()
	_validation.name = "Validation"
	_validation.set_focus_handler(focus_reference)
	_tabs.add_child(_validation)

	_localization = LocalizationPanel.new()
	_localization.name = "Localization"
	_localization.set_focus_handler(focus_reference)
	_tabs.add_child(_localization)

	_preview = PreviewPanel.new()
	_preview.name = "Preview"
	_tabs.add_child(_preview)


func _ready() -> void:
	_path_edit.text = str(ProjectSettings.get_setting(SETTING_DATABASE_PATH, ""))
	if _path_edit.text != "" and ResourceLoader.exists(_path_edit.text):
		_load_database()


func _add_button(parent: Control, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)


func _browse_database() -> void:
	var dialog := _ensure_file_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.tres ; Narrative Database"])
	_reconnect(dialog.file_selected, func(path: String) -> void:
		_path_edit.text = path
		_load_database())
	dialog.popup_centered_ratio(0.5)


func _load_database() -> void:
	var path := _path_edit.text.strip_edges()
	if path == "" or not ResourceLoader.exists(path):
		_set_status("not found: %s" % path, true)
		return
	var db := load(path) as NarrativeDatabase
	if db == null:
		_set_status("not a NarrativeDatabase: %s" % path, true)
		return
	_db = db
	ProjectSettings.set_setting(SETTING_DATABASE_PATH, path)
	ProjectSettings.save()
	_overview.show_database(db)
	_localization.show_database(db)
	_preview.set_database(db)
	_set_status("loaded %s (set as project database)" % path.get_file(), false)


func _validate() -> void:
	if not _require_db():
		return
	var issues := NarrativeValidator.new().validate(_db)
	_validation.show_issues(issues)
	_tabs.current_tab = _validation.get_index()
	_set_status("%d error(s), %d warning(s)" % [
		NarrativeValidator.count_severity(issues, "error"),
		NarrativeValidator.count_severity(issues, "warning"),
	], NarrativeValidator.count_severity(issues, "error") > 0)


func _export_csv() -> void:
	if not _require_db():
		return
	if _db.localization_tables.is_empty() or _db.localization_tables[0] == null:
		_set_status("database has no localization tables", true)
		return
	var dialog := _ensure_file_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.csv ; Localization CSV"])
	_reconnect(dialog.file_selected, func(path: String) -> void:
		var err := CsvExporter.export_table(_db.localization_tables[0], path)
		_set_status("exported table '%s' -> %s" % [_db.localization_tables[0].id, path.get_file()] if err == OK else "export failed: %s" % error_string(err), err != OK))
	dialog.popup_centered_ratio(0.5)


func _import_csv() -> void:
	if not _require_db():
		return
	var dialog := _ensure_file_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.csv ; Localization CSV"])
	_reconnect(dialog.file_selected, func(path: String) -> void:
		if _db.localization_tables.is_empty():
			_db.localization_tables.append(NarrativeLocalizationTable.new())
		var result := CsvImporter.import_into(_db.localization_tables[0], path)
		if not result.ok:
			_set_status("import failed: %s" % str(result.error), true)
			return
		var save_err := OK
		if _db.resource_path != "" and not _db.resource_path.contains("::"):
			save_err = ResourceSaver.save(_db)
		_set_status("imported %d key(s), %d locale(s)%s" % [
			result.keys, result.locales.size(),
			" (saved)" if save_err == OK and _db.resource_path != "" else "",
		], false)
		_overview.show_database(_db)
		_localization.show_database(_db)
		_preview.set_database(_db))  # imported locales must reach the language picker
	dialog.popup_centered_ratio(0.5)


func _import_script() -> void:
	if not _require_db():
		return
	var dialog := _ensure_file_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.ndlg, *.txt ; Narrative Dialogue Script"])
	_reconnect(dialog.file_selected, func(path: String) -> void:
		var report := ScriptParser.import_file(_db, path)
		if not report.ok:
			var first: Dictionary = report.errors[0] if not report.errors.is_empty() else {"line": 0, "message": "unknown"}
			_set_status("script import failed — line %d: %s (%d error(s), database untouched)" % [int(first.line), str(first.message), report.errors.size()], true)
			return
		var save_err := OK
		if _db.resource_path != "" and not _db.resource_path.contains("::"):
			save_err = ResourceSaver.save(_db)
		_set_status("script imported: %d new, %d replaced%s" % [
			report.imported.size(), report.replaced.size(),
			" (saved)" if save_err == OK and _db.resource_path != "" else "",
		], false)
		_overview.show_database(_db)
		_localization.show_database(_db)
		_preview.set_database(_db))
	dialog.popup_centered_ratio(0.5)


## Injected by plugin.gd so validation/localization rows can jump to the
## graph view. Tests may inject a graph editor instance directly.
func set_graph_editor(graph_editor: Control) -> void:
	_graph_editor = graph_editor


## Focuses the resource behind a parse_where-shaped ref: opens it in the
## Inspector and, for dialogue nodes, jumps the main-screen graph view to it.
func focus_reference(ref: Dictionary) -> void:
	if _db == null:
		return
	var resolved := NarrativeValidator.resolve_reference(_db, ref)
	var resource: Resource = resolved.resource
	if resource == null:
		_set_status("cannot focus '%s' — resource not found" % str(ref.get("id", "?")), true)
		return
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(resource)
	if str(resolved.dialogue_id) != "" and _graph_editor != null:
		if Engine.is_editor_hint():
			EditorInterface.set_main_screen_editor("Narrative")
		_graph_editor.focus_node(str(resolved.dialogue_id), str(resolved.node_id))
	_set_status("focused %s" % _describe_ref(ref), false)


func _describe_ref(ref: Dictionary) -> String:
	var text := "%s '%s'" % [str(ref.get("category", "?")), str(ref.get("id", "?"))]
	for key in ["node", "choice", "objective"]:
		if ref.has(key):
			text += " > %s '%s'" % [key, str(ref[key])]
	return text


func _require_db() -> bool:
	if _db == null:
		_set_status("load a database first", true)
		return false
	return true


func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.5, 0.5) if is_error else Color(1, 1, 1, 0.7)


func _ensure_file_dialog() -> EditorFileDialog:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		add_child(_file_dialog)
	return _file_dialog


## EditorFileDialog is reused across actions: swap the file_selected handler.
func _reconnect(sig: Signal, handler: Callable) -> void:
	for connection in sig.get_connections():
		sig.disconnect(connection.callable)
	sig.connect(handler)
