@tool
extends RefCounted
## Pure graph-editing operations on a NarrativeDialogue — no UI, no @tool,
## no editor dependencies, so every operation is headless-testable.
## dialogue_graph_editor.gd is a thin GraphEdit shell over this.
##
## Node canvas positions are stored in DialogueNode.metadata["graph_position"]
## (a Vector2 — serializes fine in .tres, ignored by the save system).

const POSITION_KEY := "graph_position"

const LAYOUT_ORIGIN := Vector2(60, 80)
const LAYOUT_COLUMN_WIDTH := 360.0
const LAYOUT_ROW_HEIGHT := 240.0


# --- ids ---


static func generate_node_id(dialogue: NarrativeDialogue) -> String:
	var index := dialogue.nodes.size() + 1
	while dialogue.has_node_id("n%d" % index):
		index += 1
	return "n%d" % index


static func generate_dialogue_id(db: NarrativeDatabase) -> String:
	var index := db.dialogues.size() + 1
	while db.get_dialogue("dialogue_%d" % index) != null:
		index += 1
	return "dialogue_%d" % index


static func is_valid_id(id: String) -> bool:
	if id == "":
		return false
	for i in id.length():
		var c := id[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_" or c == "."
		if not ok:
			return false
	return true


# --- structure ---


## Appends a new node (auto id when empty). Returns null on id collision.
static func add_node(dialogue: NarrativeDialogue, node_id := "", position := Vector2.ZERO) -> NarrativeDialogueNode:
	var id := node_id if node_id != "" else generate_node_id(dialogue)
	if not is_valid_id(id):
		push_error("Narrative graph: invalid node id '%s'" % id)
		return null
	if dialogue.has_node_id(id):
		push_error("Narrative graph: node id '%s' already exists in dialogue '%s'" % [id, dialogue.id])
		return null
	var node := NarrativeDialogueNode.new()
	node.id = id
	set_position(node, position)
	dialogue.nodes.append(node)
	if dialogue.start_node_id == "" and dialogue.nodes.size() == 1:
		dialogue.start_node_id = id
	return node


## Removes a node and clears every link pointing at it.
## Returns {removed: bool, cleaned_links: int, was_start: bool}.
static func delete_node(dialogue: NarrativeDialogue, node_id: String) -> Dictionary:
	var report := {"removed": false, "cleaned_links": 0, "was_start": false}
	var index := -1
	for i in dialogue.nodes.size():
		if dialogue.nodes[i] != null and dialogue.nodes[i].id == node_id:
			index = i
			break
	if index < 0:
		return report
	dialogue.nodes.remove_at(index)
	report.removed = true
	for node in dialogue.nodes:
		if node == null:
			continue
		if node.next_node_id == node_id:
			node.next_node_id = ""
			report.cleaned_links += 1
		for choice in node.choices:
			if choice != null and choice.target_node_id == node_id:
				choice.target_node_id = ""
				report.cleaned_links += 1
	if dialogue.start_node_id == node_id:
		dialogue.start_node_id = ""
		report.was_start = true
	return report


## Creates a dialogue with one start node and appends it to the database.
static func create_dialogue(db: NarrativeDatabase, dialogue_id := "") -> NarrativeDialogue:
	var id := dialogue_id if dialogue_id != "" else generate_dialogue_id(db)
	if not is_valid_id(id):
		push_error("Narrative graph: invalid dialogue id '%s'" % id)
		return null
	if db.get_dialogue(id) != null:
		push_error("Narrative graph: dialogue id '%s' already exists" % id)
		return null
	var dialogue := NarrativeDialogue.new()
	dialogue.id = id
	dialogue.title = id
	db.dialogues.append(dialogue)
	add_node(dialogue, "start", Vector2(LAYOUT_ORIGIN))
	return dialogue


# --- links ---


## to_id == "" disconnects. Both endpoints must exist otherwise.
static func set_next(dialogue: NarrativeDialogue, from_id: String, to_id: String) -> bool:
	var from_node := dialogue.get_node_by_id(from_id)
	if from_node == null:
		push_error("Narrative graph: unknown node '%s'" % from_id)
		return false
	if to_id != "" and not dialogue.has_node_id(to_id):
		push_error("Narrative graph: unknown target node '%s'" % to_id)
		return false
	from_node.next_node_id = to_id
	return true


## to_id == "" disconnects that choice.
static func set_choice_target(dialogue: NarrativeDialogue, from_id: String, choice_index: int, to_id: String) -> bool:
	var from_node := dialogue.get_node_by_id(from_id)
	if from_node == null:
		push_error("Narrative graph: unknown node '%s'" % from_id)
		return false
	if choice_index < 0 or choice_index >= from_node.choices.size() or from_node.choices[choice_index] == null:
		push_error("Narrative graph: node '%s' has no choice index %d" % [from_id, choice_index])
		return false
	if to_id != "" and not dialogue.has_node_id(to_id):
		push_error("Narrative graph: unknown target node '%s'" % to_id)
		return false
	from_node.choices[choice_index].target_node_id = to_id
	return true


static func set_start(dialogue: NarrativeDialogue, node_id: String) -> bool:
	if not dialogue.has_node_id(node_id):
		push_error("Narrative graph: unknown node '%s'" % node_id)
		return false
	dialogue.start_node_id = node_id
	return true


## Every resolvable link as {from_id, port, to_id}.
## port 0 = next_node_id, port 1..N = choices[port - 1].
## Links to missing nodes are omitted (the validator reports those).
static func connections(dialogue: NarrativeDialogue) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in dialogue.nodes:
		if node == null or node.id == "":
			continue
		if node.next_node_id != "" and dialogue.has_node_id(node.next_node_id):
			result.append({"from_id": node.id, "port": 0, "to_id": node.next_node_id})
		for i in node.choices.size():
			var choice := node.choices[i]
			if choice != null and choice.target_node_id != "" and dialogue.has_node_id(choice.target_node_id):
				result.append({"from_id": node.id, "port": i + 1, "to_id": choice.target_node_id})
	return result


# --- canvas positions ---


static func has_position(node: NarrativeDialogueNode) -> bool:
	return typeof(node.metadata.get(POSITION_KEY)) == TYPE_VECTOR2


static func get_position(node: NarrativeDialogueNode) -> Vector2:
	var value: Variant = node.metadata.get(POSITION_KEY)
	return value if typeof(value) == TYPE_VECTOR2 else Vector2.ZERO


static func set_position(node: NarrativeDialogueNode, position: Vector2) -> void:
	node.metadata[POSITION_KEY] = position


## Assigns positions to nodes that have none: BFS layers from the start node
## (depth -> column, breadth -> row), unreachable nodes parked in the last
## column. Deterministic. Returns how many nodes were positioned.
static func auto_layout(dialogue: NarrativeDialogue) -> int:
	var depths := {}
	var max_depth := 0
	if dialogue.has_node_id(dialogue.start_node_id):
		var frontier: Array[String] = [dialogue.start_node_id]
		depths[dialogue.start_node_id] = 0
		while not frontier.is_empty():
			var current_id: String = frontier.pop_front()
			var current_depth: int = depths[current_id]
			max_depth = maxi(max_depth, current_depth)
			var node := dialogue.get_node_by_id(current_id)
			if node == null:
				continue
			var neighbors: Array[String] = []
			if node.next_node_id != "" and dialogue.has_node_id(node.next_node_id):
				neighbors.append(node.next_node_id)
			for choice in node.choices:
				if choice != null and choice.target_node_id != "" and dialogue.has_node_id(choice.target_node_id):
					neighbors.append(choice.target_node_id)
			for neighbor in neighbors:
				if not depths.has(neighbor):
					depths[neighbor] = current_depth + 1
					frontier.append(neighbor)

	var rows := {}  # depth -> next row index
	var positioned := 0
	for node in dialogue.nodes:
		if node == null or has_position(node):
			continue
		var depth: int = depths.get(node.id, max_depth + 1)
		var row: int = rows.get(depth, 0)
		rows[depth] = row + 1
		set_position(node, LAYOUT_ORIGIN + Vector2(depth * LAYOUT_COLUMN_WIDTH, row * LAYOUT_ROW_HEIGHT))
		positioned += 1
	return positioned
