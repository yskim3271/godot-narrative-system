@tool
extends RefCounted
## Imports localization CSV (header: key,<locale>,...) into a
## NarrativeLocalizationTable. Strips the UTF-8 BOM Excel likes to add.
## Empty cells are skipped (they do not erase existing translations);
## pass merge = false to clear the table first.


## Returns {ok: bool, keys: int, locales: PackedStringArray, error: String}.
static func import_into(table: NarrativeLocalizationTable, path: String, merge := true) -> Dictionary:
	if table == null:
		return _fail("table is null")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot open '%s' (%s)" % [path, error_string(FileAccess.get_open_error())])

	var header := file.get_csv_line()
	if header.size() > 0:
		# UTF-8 BOM arrives as U+FEFF on the first cell.
		header[0] = header[0].trim_prefix(String.chr(0xFEFF)).strip_edges()
	if header.size() < 2 or header[0].to_lower() != "key":
		return _fail("invalid header — expected 'key,<locale>,...', got '%s'" % ",".join(header))

	var locales := PackedStringArray()
	for i in range(1, header.size()):
		var locale := header[i].strip_edges()
		if locale == "":
			return _fail("empty locale name in header column %d" % (i + 1))
		locales.append(locale)

	if not merge:
		table.entries.clear()

	var imported_keys := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 0:
			continue
		var key := row[0].strip_edges()
		if key == "":
			continue  # blank/trailing line
		var any := false
		for i in locales.size():
			var column := i + 1
			if column >= row.size():
				break
			var value := row[column]
			if value != "":
				table.set_text(key, locales[i], value)
				any = true
		if any:
			imported_keys += 1
	file.close()
	return {"ok": true, "keys": imported_keys, "locales": locales, "error": ""}


static func _fail(message: String) -> Dictionary:
	push_error("Narrative CSV import: %s" % message)
	return {"ok": false, "keys": 0, "locales": PackedStringArray(), "error": message}
