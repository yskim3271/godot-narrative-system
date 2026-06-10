class_name NarrativeSequencer
extends RefCounted
## Executes sequencer command lines attached to dialogue nodes
## (e.g. [code]wait(0.5)\nset_expression("guard","angry")[/code]).
##
## Commands run SEQUENTIALLY alongside the presented line (the runner emits
## line_presented first, then starts the run without awaiting it).
## advance()/select_choice() cancels the in-flight run: cancellation bumps a
## run-id token checked after every await, so no further commands execute —
## an in-flight wait simply expires silently.
##
## Command lines are parsed by the shared DSL parser (calls only) and their
## arguments are full DSL expressions evaluated against the narrative state.
## Extend with register_command(name, callable) — the callable receives one
## Array of evaluated args and may await.

signal sequence_event(event_name: String, args: Array)
signal run_finished(label: String)

const Evaluator := preload("dsl/evaluator.gd")

var _evaluator: Evaluator
var _commands: Dictionary = {}  # name -> Callable(args: Array)
var _run_id := 0
var _running := false


func setup(evaluator: Evaluator) -> void:
	_evaluator = evaluator


## Registers a sequencer command. Collisions are rejected unless override.
func register_command(name: String, handler: Callable, override := false) -> bool:
	if name == "" or not name.is_valid_ascii_identifier():
		push_error("Narrative: invalid sequencer command name '%s'" % name)
		return false
	if not handler.is_valid():
		push_error("Narrative: cannot register sequencer command '%s' — callable is invalid" % name)
		return false
	if _commands.has(name) and not override:
		push_error("Narrative: sequencer command '%s' is already registered (pass override = true to replace it)" % name)
		return false
	_commands[name] = handler
	return true


func has_command(name: String) -> bool:
	return _commands.has(name)


func registered_commands() -> PackedStringArray:
	var names := PackedStringArray()
	for name: String in _commands:
		names.append(name)
	names.sort()
	return names


func is_running() -> bool:
	return _running


## Stops the current run: no further commands of that run will execute.
func cancel_current() -> void:
	_run_id += 1
	_running = false


## Parses and starts a command run. Does not await — callers continue
## immediately while the run progresses across frames.
func start_run(source: String, label := "") -> void:
	cancel_current()
	if source.strip_edges() == "":
		return
	var parsed := _evaluator.parse_sequence_cached(source)
	if not parsed.ok:
		push_warning("Narrative sequencer [%s]: parse error at %d: %s" % [label, parsed.error.pos, parsed.error.message])
		return
	_execute(parsed.statements, _run_id, label)


func _execute(statements: Array, token: int, label: String) -> void:
	_running = true
	for stmt in statements:
		if token != _run_id:
			return  # cancelled
		var name: String = stmt[1]
		if not _commands.has(name):
			push_warning("Narrative sequencer [%s]: unknown command '%s' — skipped" % [label, name])
			continue
		var args: Array = []
		var arg_failed := false
		for arg_ast in stmt[2]:
			var result := _evaluator.evaluate(arg_ast)
			if not result.ok:
				push_warning("Narrative sequencer [%s]: argument error in '%s': %s — command skipped" % [label, name, result.error])
				arg_failed = true
				break
			args.append(result.value)
		if arg_failed:
			continue
		var handler: Callable = _commands[name]
		if not handler.is_valid():
			push_warning("Narrative sequencer [%s]: command '%s' is no longer valid — skipped" % [label, name])
			continue
		await handler.call(args)
		if token != _run_id:
			return
	if token == _run_id:
		_running = false
		run_finished.emit(label)
