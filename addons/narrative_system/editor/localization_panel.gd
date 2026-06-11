@tool
extends VBoxContainer
## Localization tab: lists every translatable unit with missing translations
## (per locale), built from localization_report.gd. Double-click a row to
## focus the offending resource (Inspector + graph view via the focus
## handler injected by narrative_panel.gd).

const LocalizationReport := preload("localization_report.gd")

const FILTER_ALL := "(all locales)"

var _db: NarrativeDatabase
var _focus_handler := Callable()
var _summary: Label
var _filter: OptionButton
var _list: Tree
var _report: Dictionary = {}


func _init() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var filter_label := Label.new()
	filter_label.text = "Locale:"
	toolbar.add_child(filter_label)

	_filter = OptionButton.new()
	_filter.custom_minimum_size = Vector2(120, 0)
	_filter.item_selected.connect(func(_index: int) -> void: _rebuild_list())
	toolbar.add_child(_filter)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(func() -> void: show_database(_db))
	toolbar.add_child(refresh)

	_summary = Label.new()
	_summary.text = "Load a database to analyze translation coverage."
	_summary.modulate = Color(1, 1, 1, 0.7)
	toolbar.add_child(_summary)

	_list = Tree.new()
	_list.columns = 3
	_list.set_column_title(0, "Where")
	_list.set_column_title(1, "Key")
	_list.set_column_title(2, "Missing locales")
	_list.set_column_expand_ratio(0, 3)
	_list.set_column_expand_ratio(1, 3)
	_list.set_column_expand_ratio(2, 1)
	_list.column_titles_visible = true
	_list.hide_root = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	add_child(_list)


## Called by narrative_panel: routes a parse_where-shaped ref to the
## Inspector / graph editor.
func set_focus_handler(handler: Callable) -> void:
	_focus_handler = handler


## Recomputes the coverage report. Pass null to clear.
func show_database(db: NarrativeDatabase) -> void:
	_db = db
	var selected := _selected_locale()
	_report = {}
	if _db != null:
		_report = LocalizationReport.build(_db)
	_refresh_filter(selected)
	_rebuild_list()


## Rows currently shown (tests). Each is the report row Dictionary.
func visible_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var item := _list.get_root().get_first_child() if _list.get_root() != null else null
	while item != null:
		rows.append(item.get_metadata(0))
		item = item.get_next()
	return rows


func _selected_locale() -> String:
	if _filter.selected < 0:
		return FILTER_ALL
	return _filter.get_item_text(_filter.selected)


func _refresh_filter(previous: String) -> void:
	_filter.clear()
	_filter.add_item(FILTER_ALL)
	if _report.is_empty():
		return
	for locale: String in _report.locales:
		_filter.add_item(locale)
	for i in _filter.item_count:
		if _filter.get_item_text(i) == previous:
			_filter.select(i)
			return


func _rebuild_list() -> void:
	_list.clear()
	_list.create_item()
	if _report.is_empty():
		_summary.text = "Load a database to analyze translation coverage."
		return
	var locale := _selected_locale()
	var shown := 0
	for row: Dictionary in _report.rows:
		var missing: PackedStringArray = row.missing
		if locale != FILTER_ALL and not missing.has(locale):
			continue
		var item := _list.create_item()
		item.set_text(0, str(row.where))
		item.set_text(1, str(row.key))
		item.set_text(2, ", ".join(missing))
		item.set_custom_color(2, Color(1.0, 0.85, 0.4))
		item.set_tooltip_text(0, "Double-click to focus this resource")
		item.set_metadata(0, row)
		shown += 1

	var parts := PackedStringArray()
	for loc: String in _report.locales:
		var count := int(_report.missing_by_locale.get(loc, 0))
		if count > 0:
			parts.append("%s: %d" % [loc, count])
	var covered: int = int(_report.units) - (_report.rows as Array).size()
	_summary.text = "%d/%d unit(s) fully translated" % [covered, int(_report.units)] \
		+ ("  ·  missing — " + ", ".join(parts) if not parts.is_empty() else "  ·  ✓ complete") \
		+ ("  ·  showing %d row(s)" % shown if locale != FILTER_ALL else "")


func _on_item_activated() -> void:
	var selected := _list.get_selected()
	if selected == null or _focus_handler.is_null():
		return
	var row: Variant = selected.get_metadata(0)
	if typeof(row) == TYPE_DICTIONARY and (row as Dictionary).has("ref"):
		_focus_handler.call((row as Dictionary).ref)
