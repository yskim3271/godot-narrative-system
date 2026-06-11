@tool
class_name NarrativeDialogue
extends Resource
## One dialogue graph: a set of [NarrativeDialogueNode]s linked by ids.
##
## Authoring data is immutable at runtime. The id index below is a runtime
## cache (not exported, never saved) and rebuilds itself if the node array
## size changes (editor tooling convenience).

## Unique id used by start_dialogue() (charset: [a-zA-Z0-9_.]).
@export var id := ""
## Human-readable title (authoring/editor only).
@export var title := ""
## Node where the dialogue begins.
@export var start_node_id := ""
## All nodes of this graph. Order is irrelevant at runtime; links use ids.
@export var nodes: Array[NarrativeDialogueNode] = []
## Free-form authoring metadata.
@export var metadata: Dictionary = {}

var _node_index: Dictionary = {}
var _indexed_count := -1


## Node lookup by id. Returns null when missing (callers report the error
## with their own context).
func get_node_by_id(node_id: String) -> NarrativeDialogueNode:
	_ensure_index()
	return _node_index.get(node_id)


func has_node_id(node_id: String) -> bool:
	_ensure_index()
	return _node_index.has(node_id)


## Forces the id index to rebuild on the next lookup. The size-based
## auto-rebuild misses an in-place id change (rename), so editor tooling that
## renames a node must call this afterwards.
func invalidate_index() -> void:
	_indexed_count = -1


func _ensure_index() -> void:
	if _indexed_count == nodes.size():
		return
	_node_index.clear()
	for node in nodes:
		if node == null:
			continue
		if _node_index.has(node.id):
			push_error("NarrativeDialogue '%s': duplicate node id '%s' (first definition wins)" % [id, node.id])
			continue
		_node_index[node.id] = node
	_indexed_count = nodes.size()
