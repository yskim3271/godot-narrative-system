@tool
extends VBoxContainer
## Validation tab: summary + issue list (red errors, yellow warnings).

var _summary: Label
var _list: ItemList


func _init() -> void:
	_summary = Label.new()
	_summary.text = "Run Validate from the toolbar."
	add_child(_summary)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list)


func show_issues(issues: Array[Dictionary]) -> void:
	_list.clear()
	var errors := NarrativeValidator.count_severity(issues, "error")
	var warnings := NarrativeValidator.count_severity(issues, "warning")
	if issues.is_empty():
		_summary.text = "✓ No issues found."
		return
	_summary.text = "%d error(s), %d warning(s)" % [errors, warnings]
	for issue in issues:
		var index := _list.add_item(NarrativeValidator.format_issue(issue))
		_list.set_item_custom_fg_color(
			index,
			Color(1.0, 0.45, 0.45) if issue.severity == "error" else Color(1.0, 0.85, 0.4)
		)
		_list.set_item_tooltip(index, str(issue.where))
