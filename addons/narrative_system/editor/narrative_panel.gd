@tool
extends VBoxContainer
## Bottom-panel shell: database path bar + tabs (Database overview /
## Validation) + CSV import/export. Built entirely in code; never touches
## the runtime autoload (loads the database itself from the project setting).

const SETTING_DATABASE_PATH := "narrative_system/database_path"
const DatabaseEditor := preload("database_editor.gd")
const ValidationPanel := preload("validation_panel.gd")
const CsvExporter := preload("../import_export/csv_exporter.gd")
const CsvImporter := preload("../import_export/csv_importer.gd")

var _db: NarrativeDatabase
var _path_edit: LineEdit
var _status: Label
var _tabs: TabContainer
var _overview: Tree
var _validation: VBoxContainer
var _file_dialog: EditorFileDialog


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
	_tabs.add_child(_validation)


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
		_overview.show_database(_db))
	dialog.popup_centered_ratio(0.5)


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
