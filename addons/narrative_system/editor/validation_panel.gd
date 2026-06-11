@tool
extends VBoxContainer
## Validation tab: summary + issue list (red errors, yellow warnings).
## Double-click an issue to focus the offending resource (Inspector + graph
## view via the focus handler injected by narrative_panel.gd).

var _summary: Label
var _list: ItemList
var _focus_handler := Callable()


func _init() -> void:
	_summary = Label.new()
	_summary.text = "Run Validate from the toolbar."
	add_child(_summary)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	add_child(_list)


## Called by narrative_panel: routes a parse_where-shaped ref to the
## Inspector / graph editor.
func set_focus_handler(handler: Callable) -> void:
	_focus_handler = handler


func show_issues(issues: Array[Dictionary]) -> void:
	_list.clear()
	var errors := NarrativeValidator.count_severity(issues, "error")
	var warnings := NarrativeValidator.count_severity(issues, "warning")
	if issues.is_empty():
		_summary.text = "✓ No issues found."
		return
	_summary.text = "%d error(s), %d warning(s) — double-click an issue to focus it" % [errors, warnings]
	for issue in issues:
		var index := _list.add_item(NarrativeValidator.format_issue(issue))
		_list.set_item_custom_fg_color(
			index,
			Color(1.0, 0.45, 0.45) if issue.severity == "error" else Color(1.0, 0.85, 0.4)
		)
		_list.set_item_tooltip(index, "%s\nDouble-click to focus this resource" % str(issue.where))
		_list.set_item_metadata(index, issue)


func _on_item_activated(index: int) -> void:
	if _focus_handler.is_null():
		return
	var issue: Variant = _list.get_item_metadata(index)
	if typeof(issue) != TYPE_DICTIONARY:
		return
	var ref := NarrativeValidator.parse_where(str((issue as Dictionary).where))
	if not ref.is_empty():
		_focus_handler.call(ref)
