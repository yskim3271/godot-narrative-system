@tool
extends Tree
## Database overview tab: categories with counts, entries by id.
## Double-click an entry to open it in the Inspector.


func _init() -> void:
	columns = 2
	set_column_title(0, "Entry")
	set_column_title(1, "Info")
	column_titles_visible = true
	hide_root = true
	item_activated.connect(_on_item_activated)


func show_database(db: NarrativeDatabase) -> void:
	clear()
	if db == null:
		return
	var root := create_item()
	_add_category(root, "Characters", db.characters, func(c) -> String: return c.display_name)
	_add_category(root, "Dialogues", db.dialogues, func(d) -> String: return "%d node(s), start: %s" % [d.nodes.size(), d.start_node_id])
	_add_category(root, "Quests", db.quests, func(q) -> String: return "%d objective(s)" % q.objectives.size())
	_add_category(root, "Variables", db.variables, func(v) -> String: return "%s = %s" % [NarrativeVariable.Type.keys()[v.type], str(v.get_default())])
	_add_category(root, "Localization tables", db.localization_tables, func(t) -> String: return "%d key(s), locales: %s" % [t.entries.size(), ", ".join(t.collect_locales())])


func _add_category(root: TreeItem, title: String, items: Array, info: Callable) -> void:
	var header := create_item(root)
	header.set_text(0, "%s (%d)" % [title, items.size()])
	header.set_selectable(0, false)
	header.set_selectable(1, false)
	for item in items:
		if item == null:
			continue
		var row := create_item(header)
		row.set_text(0, str(item.id))
		row.set_text(1, str(info.call(item)))
		row.set_metadata(0, item)


func _on_item_activated() -> void:
	var selected := get_selected()
	if selected == null:
		return
	var resource: Variant = selected.get_metadata(0)
	if resource is Resource and Engine.is_editor_hint():
		EditorInterface.edit_resource(resource)
