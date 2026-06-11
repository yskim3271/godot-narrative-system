@tool
extends RefCounted
## Text authoring format (.ndlg) for dialogues — writer-friendly plain text
## that imports into NarrativeDialogue resources (and exports back, so the
## two authoring paths can be mixed). See docs/text_script.md.
##
## Format (line-based, indentation ignored, full line `#` = comment):
##
##   dialogue guard_talk
##   title 경비병 대화
##   start g_first
##
##   node g_first
##   speaker guard
##   if not has_seen("guard_talk", "g_first")
##   do met_guard = true
##   text 처음 보는 얼굴이군.
##   text 무슨 일로 왔나?          # repeated text = appended line
##   seq set_expression("guard", "angry")
##   next g_menu
##
##   node g_menu
##   text 용건을 말해보게.
##   choice c_quest -> q_give      # "-> target" / "->" or no arrow = end dialogue
##     text 일거리가 있나?          # after `choice`, text/if/do/key attach to it
##     if quest_state("rat_hunt") == "inactive"
##     show_disabled
##
## Rules: node-level text/if/do/key must appear BEFORE the node's first
## choice; speaker/seq/next are always node-level. One `if`/`key` per target.
## Import is atomic: any parse error leaves the database untouched.


## Returns {ok: bool, dialogues: Array[NarrativeDialogue],
##          errors: [{line: int, message: String}]}.
static func parse_text(source: String) -> Dictionary:
	var dialogues: Array[NarrativeDialogue] = []
	var seen_dialogue_ids := {}
	var errors: Array[Dictionary] = []

	var dialogue: NarrativeDialogue = null
	var dialogue_line := 0
	var node: NarrativeDialogueNode = null
	var choice: NarrativeChoice = null
	var node_flags := {}
	var choice_flags := {}

	var lines := source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for line_index in lines.size():
		var line_number := line_index + 1
		var raw := lines[line_index]
		if line_index == 0:
			raw = raw.trim_prefix(String.chr(0xFEFF))
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var space := line.find(" ")
		var keyword := line if space < 0 else line.substr(0, space)
		var rest := "" if space < 0 else line.substr(space + 1).strip_edges()

		match keyword:
			"dialogue":
				_finalize_dialogue(dialogue, dialogue_line, errors)
				dialogue = null
				node = null
				choice = null
				if not _valid_id(rest):
					_err(errors, line_number, "invalid dialogue id '%s'" % rest)
					continue
				if seen_dialogue_ids.has(rest):
					_err(errors, line_number, "duplicate dialogue id '%s'" % rest)
					continue
				seen_dialogue_ids[rest] = true
				dialogue = NarrativeDialogue.new()
				dialogue.id = rest
				dialogue.title = rest
				dialogue_line = line_number
				dialogues.append(dialogue)
			"title":
				if dialogue == null:
					_err(errors, line_number, "'title' before any 'dialogue'")
				else:
					dialogue.title = rest
			"start":
				if dialogue == null:
					_err(errors, line_number, "'start' before any 'dialogue'")
				elif not _valid_id(rest):
					_err(errors, line_number, "invalid start node id '%s'" % rest)
				else:
					dialogue.start_node_id = rest
			"node":
				if dialogue == null:
					_err(errors, line_number, "'node' before any 'dialogue'")
					continue
				choice = null
				node_flags = {}
				node = NarrativeDialogueNode.new()
				if not _valid_id(rest):
					_err(errors, line_number, "invalid node id '%s'" % rest)
					continue
				node.id = rest
				if dialogue.has_node_id(rest):
					_err(errors, line_number, "duplicate node id '%s' in dialogue '%s'" % [rest, dialogue.id])
					continue  # node stays current so following lines parse, but is not added
				dialogue.nodes.append(node)
			"speaker":
				if node == null:
					_err(errors, line_number, "'speaker' before any 'node'")
				else:
					node.speaker_id = rest
			"next":
				if node == null:
					_err(errors, line_number, "'next' before any 'node'")
				elif not _valid_id(rest):
					_err(errors, line_number, "invalid next node id '%s'" % rest)
				else:
					node.next_node_id = rest
			"seq":
				if node == null:
					_err(errors, line_number, "'seq' before any 'node'")
				else:
					node.sequencer_commands = _append(node.sequencer_commands, rest)
			"text":
				if choice != null:
					choice.text = _append(choice.text, rest)
				elif node != null:
					if not node.choices.is_empty():
						_err(errors, line_number, "node-level 'text' must appear before the first choice")
					else:
						node.text = _append(node.text, rest)
				else:
					_err(errors, line_number, "'text' before any 'node'")
			"if":
				if choice != null:
					if choice_flags.has("if"):
						_err(errors, line_number, "choice '%s' already has an 'if' (combine with 'and')" % choice.id)
					else:
						choice.condition = rest
						choice_flags["if"] = true
				elif node != null:
					if node_flags.has("if"):
						_err(errors, line_number, "node '%s' already has an 'if' (combine with 'and')" % node.id)
					elif not node.choices.is_empty():
						_err(errors, line_number, "node-level 'if' must appear before the first choice")
					else:
						node.conditions = rest
						node_flags["if"] = true
				else:
					_err(errors, line_number, "'if' before any 'node'")
			"do":
				if choice != null:
					choice.actions = _append(choice.actions, rest)
				elif node != null:
					if not node.choices.is_empty():
						_err(errors, line_number, "node-level 'do' must appear before the first choice")
					else:
						node.actions = _append(node.actions, rest)
				else:
					_err(errors, line_number, "'do' before any 'node'")
			"key":
				if choice != null:
					if choice_flags.has("key"):
						_err(errors, line_number, "choice '%s' already has a 'key'" % choice.id)
					else:
						choice.localized_text_key = rest
						choice_flags["key"] = true
				elif node != null:
					if node_flags.has("key"):
						_err(errors, line_number, "node '%s' already has a 'key'" % node.id)
					else:
						node.localized_text_key = rest
						node_flags["key"] = true
				else:
					_err(errors, line_number, "'key' before any 'node'")
			"choice":
				if node == null:
					_err(errors, line_number, "'choice' before any 'node'")
					continue
				var parsed_choice := _parse_choice_decl(rest)
				if parsed_choice.error != "":
					_err(errors, line_number, parsed_choice.error)
					continue
				var duplicate := false
				for existing in node.choices:
					if existing != null and existing.id == parsed_choice.id:
						duplicate = true
				if duplicate:
					_err(errors, line_number, "duplicate choice id '%s' in node '%s'" % [parsed_choice.id, node.id])
					continue
				choice = NarrativeChoice.new()
				choice.id = parsed_choice.id
				choice.target_node_id = parsed_choice.target
				choice_flags = {}
				node.choices.append(choice)
			"show_disabled":
				if choice == null:
					_err(errors, line_number, "'show_disabled' outside of a choice")
				else:
					choice.show_disabled = true
			_:
				_err(errors, line_number, "unknown keyword '%s'" % keyword)

	_finalize_dialogue(dialogue, dialogue_line, errors)
	return {"ok": errors.is_empty(), "dialogues": dialogues, "errors": errors}


## Parses and merges into a database. ATOMIC: any parse error returns the
## report without touching the database. Existing dialogue ids are replaced
## in place (replace_existing = true) or skipped.
static func import_text(db: NarrativeDatabase, source: String, replace_existing := true) -> Dictionary:
	var parsed := parse_text(source)
	var report := {
		"ok": parsed.ok,
		"imported": [], "replaced": [], "skipped": [],
		"errors": parsed.errors,
	}
	if not parsed.ok:
		for error in parsed.errors:
			push_error("Narrative script: line %d: %s" % [error.line, error.message])
		return report
	for dialogue in parsed.dialogues:
		var existing_index := -1
		for i in db.dialogues.size():
			if db.dialogues[i] != null and db.dialogues[i].id == dialogue.id:
				existing_index = i
				break
		if existing_index < 0:
			db.dialogues.append(dialogue)
			report.imported.append(dialogue.id)
		elif replace_existing:
			db.dialogues[existing_index] = dialogue
			report.replaced.append(dialogue.id)
		else:
			report.skipped.append(dialogue.id)
	if not report.replaced.is_empty():
		# In-place replacement keeps the array size, which the database's
		# lazy id index uses for auto-invalidation — force a rebuild.
		db.invalidate_indexes()
	return report


static func import_file(db: NarrativeDatabase, path: String, replace_existing := true) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Narrative script: file not found: %s" % path)
		return {"ok": false, "imported": [], "replaced": [], "skipped": [],
			"errors": [{"line": 0, "message": "file not found: %s" % path}]}
	return import_text(db, FileAccess.get_file_as_string(path), replace_existing)


## Round-trip export (graph positions/metadata are not part of the format).
static func export_dialogue(dialogue: NarrativeDialogue) -> String:
	var out := PackedStringArray()
	out.append("dialogue %s" % dialogue.id)
	if dialogue.title != "" and dialogue.title != dialogue.id:
		out.append("title %s" % dialogue.title)
	if dialogue.start_node_id != "":
		out.append("start %s" % dialogue.start_node_id)
	for node in dialogue.nodes:
		if node == null:
			continue
		out.append("")
		out.append("node %s" % node.id)
		if node.speaker_id != "":
			out.append("speaker %s" % node.speaker_id)
		if node.localized_text_key != "":
			out.append("key %s" % node.localized_text_key)
		if node.conditions.strip_edges() != "":
			out.append("if %s" % node.conditions.replace("\n", " ").strip_edges())
		for action_line in _split_lines(node.actions):
			out.append("do %s" % action_line)
		for text_line in _split_lines(node.text):
			out.append("text %s" % text_line)
		for seq_line in _split_lines(node.sequencer_commands):
			out.append("seq %s" % seq_line)
		if node.next_node_id != "":
			out.append("next %s" % node.next_node_id)
		for choice in node.choices:
			if choice == null:
				continue
			if choice.target_node_id != "":
				out.append("choice %s -> %s" % [choice.id, choice.target_node_id])
			else:
				out.append("choice %s ->" % choice.id)
			if choice.localized_text_key != "":
				out.append("  key %s" % choice.localized_text_key)
			if choice.condition.strip_edges() != "":
				out.append("  if %s" % choice.condition.replace("\n", " ").strip_edges())
			for action_line in _split_lines(choice.actions):
				out.append("  do %s" % action_line)
			for text_line in _split_lines(choice.text):
				out.append("  text %s" % text_line)
			if choice.show_disabled:
				out.append("  show_disabled")
	return "\n".join(out) + "\n"


# --- internals ---


static func _parse_choice_decl(rest: String) -> Dictionary:
	# "<id> -> <target>" | "<id> ->" | "<id>"
	var id := rest
	var target := ""
	var arrow := rest.find("->")
	if arrow >= 0:
		id = rest.substr(0, arrow).strip_edges()
		target = rest.substr(arrow + 2).strip_edges()
	if not _valid_id(id):
		return {"id": "", "target": "", "error": "invalid choice id '%s'" % id}
	if target != "" and not _valid_id(target):
		return {"id": "", "target": "", "error": "invalid choice target '%s'" % target}
	return {"id": id, "target": target, "error": ""}


static func _finalize_dialogue(dialogue: NarrativeDialogue, dialogue_line: int, errors: Array[Dictionary]) -> void:
	if dialogue == null:
		return
	if dialogue.nodes.is_empty():
		_err(errors, dialogue_line, "dialogue '%s' has no nodes" % dialogue.id)
		return
	if dialogue.start_node_id == "":
		dialogue.start_node_id = dialogue.nodes[0].id
	elif not dialogue.has_node_id(dialogue.start_node_id):
		_err(errors, dialogue_line, "dialogue '%s' start node '%s' does not exist" % [dialogue.id, dialogue.start_node_id])


static func _append(current: String, addition: String) -> String:
	return addition if current == "" else current + "\n" + addition


static func _split_lines(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for line in value.split("\n"):
		if line.strip_edges() != "":
			result.append(line.strip_edges())
	return result


static func _valid_id(id: String) -> bool:
	if id == "":
		return false
	for i in id.length():
		var c := id[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_" or c == "."
		if not ok:
			return false
	return true


static func _err(errors: Array[Dictionary], line: int, message: String) -> void:
	errors.append({"line": line, "message": message})
