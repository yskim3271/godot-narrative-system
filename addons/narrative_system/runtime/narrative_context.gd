class_name NarrativeContext
extends RefCounted
## Dependency hub that owns and wires all runtime subsystems.
##
## The autoload facade creates one with the real SceneTree; tests create
## their own with a code-built database (no autoload, no scenes needed).
## Subsystems receive their dependencies directly and never hold a strong
## reference back to the context (built-in DSL functions use a WeakRef),
## so the whole graph is leak-free RefCounted.

signal alert_requested(text: String)
signal bark_requested(character_id: String, text: String, attach_to: Node)

const Evaluator := preload("dsl/evaluator.gd")
const BuiltinFunctions := preload("dsl/builtin_functions.gd")
const BuiltinCommands := preload("builtin_commands.gd")

var database: NarrativeDatabase
var settings: NarrativeSettings
var state: NarrativeState
var evaluator: Evaluator
var localization: NarrativeLocalizationManager
var runner: NarrativeDialogueRunner
## Keeps the builtin-function provider alive: method Callables hold only a
## weak reference to their RefCounted target, so the registry alone would
## let this instance be freed (measured on 4.6.3 — calls turn invalid).
var builtins: RefCounted
var quests: NarrativeQuestManager
var save_manager: NarrativeSaveManager
var sequencer: NarrativeSequencer
## Keeps the builtin sequencer-command provider alive (same weak-Callable
## lifetime rule as `builtins`).
var builtin_commands: RefCounted
var scene_tree: SceneTree

## actor id -> Node, populated by NarrativeActor nodes (Phase 6).
var actor_registry: Dictionary = {}


static func create(db: NarrativeDatabase, tree: SceneTree = null) -> NarrativeContext:
	var ctx := NarrativeContext.new()
	if db == null:
		push_error("NarrativeContext.create: database is null — using an empty database")
		db = NarrativeDatabase.new()
	ctx.database = db
	ctx.settings = db.get_settings()
	ctx.scene_tree = tree

	ctx.state = NarrativeState.new()
	ctx.state.setup_from_database(db)

	ctx.localization = NarrativeLocalizationManager.new()
	ctx.localization.setup(db)

	ctx.evaluator = Evaluator.new()
	ctx.evaluator.setup(ctx.state)

	ctx.quests = NarrativeQuestManager.new()
	ctx.quests.setup(db, ctx.state, ctx.evaluator, ctx.localization)

	ctx.runner = NarrativeDialogueRunner.new()
	ctx.runner.setup(db, ctx.state, ctx.evaluator, ctx.localization)

	# Language changes re-present the current line. Wired here with a WeakRef
	# so the connection can never form a RefCounted cycle between the two
	# context-owned subsystems, regardless of Callable reference semantics.
	var runner_ref := weakref(ctx.runner)
	ctx.localization.language_changed.connect(func(locale: String) -> void:
		var live_runner: NarrativeDialogueRunner = runner_ref.get_ref()
		if live_runner != null:
			live_runner.on_language_changed(locale))

	ctx.save_manager = NarrativeSaveManager.new()
	ctx.save_manager.setup(db, ctx.state, ctx.localization, ctx.runner)

	ctx.sequencer = NarrativeSequencer.new()
	ctx.sequencer.setup(ctx.evaluator)
	ctx.runner.set_sequencer(ctx.sequencer)

	ctx.builtins = BuiltinFunctions.new()
	ctx.builtins.install(ctx)
	ctx.builtin_commands = BuiltinCommands.new()
	ctx.builtin_commands.install(ctx)
	return ctx


## Localizes and broadcasts an alert (AlertUI subscribes to alert_requested).
func request_alert(text_or_key: String) -> void:
	alert_requested.emit(localization.resolve_text_or_key(text_or_key))


## Localizes and broadcasts a bark (BarkUI subscribes to bark_requested).
## attach_to defaults to the registered actor node for character_id.
func bark(character_id: String, text_or_key: String, attach_to: Node = null) -> void:
	var target := attach_to
	if target == null:
		target = get_actor(character_id)
	bark_requested.emit(character_id, localization.resolve_text_or_key(text_or_key), target)


# --- actor registry (used by the sequencer and barks) ---


func register_actor(actor_id: String, node: Node) -> void:
	if actor_id == "":
		push_error("Narrative: cannot register actor with empty id")
		return
	if actor_registry.has(actor_id) and actor_registry[actor_id] != node:
		push_warning("Narrative: actor id '%s' re-registered to a different node" % actor_id)
	actor_registry[actor_id] = node


func unregister_actor(actor_id: String) -> void:
	actor_registry.erase(actor_id)


func get_actor(actor_id: String) -> Node:
	var node: Node = actor_registry.get(actor_id)
	if node != null and not is_instance_valid(node):
		actor_registry.erase(actor_id)
		return null
	return node
