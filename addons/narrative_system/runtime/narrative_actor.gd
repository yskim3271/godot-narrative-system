class_name NarrativeActor
extends Node
## Marker node: add as a child of an NPC/prop to register its PARENT in the
## narrative actor registry. Sequencer commands (play_animation, call_method,
## show/hide_actor, focus_camera...) and barks target registered actors.
##
## actor_id defaults to the parent node's name. Unregisters automatically
## when leaving the tree.

## Registry id; leave empty to use the parent node's name.
@export var actor_id := ""

var _ctx_ref: WeakRef


func _ready() -> void:
	if _ctx_ref != null:
		return
	var facade := get_node_or_null("/root/Narrative")
	if facade != null and facade.context != null:
		register_with(facade.context)


## Registers the parent node under actor_id (tests pass their own context).
func register_with(context) -> void:
	var target := get_parent() if get_parent() != null else self
	if actor_id == "":
		actor_id = str(target.name)
	_ctx_ref = weakref(context)
	context.register_actor(actor_id, target)


func _exit_tree() -> void:
	if _ctx_ref == null:
		return
	var ctx = _ctx_ref.get_ref()
	if ctx != null:
		ctx.unregister_actor(actor_id)
	_ctx_ref = null
