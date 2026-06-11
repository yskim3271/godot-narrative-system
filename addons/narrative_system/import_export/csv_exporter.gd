@tool
extends RefCounted
## Exports a NarrativeLocalizationTable to CSV (header: key,<locale>,...).
## Keys are sorted for stable diffs; fields are RFC-4180 quoted as needed.
## Output is UTF-8 without BOM.


static func export_table(table: NarrativeLocalizationTable, path: String, locales := PackedStringArray()) -> Error:
	if table == null:
		push_error("Narrative CSV export: table is null")
		return ERR_INVALID_PARAMETER
	var locale_list := locales if not locales.is_empty() else table.collect_locales()
	if locale_list.is_empty():
		push_warning("Narrative CSV export: table '%s' has no locales — exporting header only" % table.id)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("Narrative CSV export: cannot write '%s' (%s)" % [path, error_string(err)])
		return err

	var header: Array[String] = ["key"]
	for locale in locale_list:
		header.append(locale)
	file.store_line(_join(header))

	var keys: Array = table.entries.keys()
	keys.sort()
	for key in keys:
		var row: Array[String] = [str(key)]
		for locale in locale_list:
			row.append(table.get_text(str(key), locale))
		file.store_line(_join(row))
	file.close()
	return OK


static func _join(fields: Array[String]) -> String:
	var escaped: Array[String] = []
	for field in fields:
		escaped.append(_escape(field))
	return ",".join(escaped)


static func _escape(field: String) -> String:
	if field.contains(",") or field.contains("\"") or field.contains("\n"):
		return "\"%s\"" % field.replace("\"", "\"\"")
	return field
