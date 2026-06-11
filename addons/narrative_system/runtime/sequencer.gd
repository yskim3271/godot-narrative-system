@tool
class_name NarrativeSequencer
extends RefCounted
## Executes sequencer command lines attached to dialogue nodes
## (e.g. [code]wait(0.5)\nset_expression("guard","angry")[/code]).
##
## Plain lines run SEQUENTIALLY alongside the presented line (the runner emits
## line_presented first, then starts the run without awaiting it). Two
## decorations schedule lines in PARALLEL with that sequential thread
## (Unity Dialogue System parity):
##   cmd(...) @ 1.5               starts 1.5s after the run starts
##   cmd(...) @ message("ready")  starts when message "ready" is broadcast
##   cmd(...) -> "done"           broadcasts "done" when the line finishes
##                                (also fired when the command was skipped,
##                                so a typo can never deadlock a waiter)
## Messages come from -> decorations or from game code via send_message().
## run_finished fires once the sequential thread AND every scheduled line
## are done. advance()/select_choice() cancels the whole in-flight run:
## cancellation bumps a run-id token checked after every await, so no
## further commands execute — in-flight waits/timers expire silently and
## message waiters are flushed.
##
## Command lines are parsed by the shared DSL parser (calls only) and their
## arguments are full DSL expressions evaluated against the narrative state.
## Extend with register_command(name, callable) — the callable receives one
## Array of evaluated args and may await.

signal sequence_event(event_name: String, args: Array)
signal run_finished(label: String)
## A sequencer message was broadcast (-> decoration or send_message()).
signal sequencer_message(message: String)
## Internal: releases @message waiters. Also fired with "" on cancellation
## so suspended waiters wake up and observe the stale run token.
signal _release_message(message: String)

const Evaluator := preload("dsl/evaluator.gd")

var _evaluator: Evaluator
var _tree: SceneTree  # for @time timers; null in tree-less contexts
var _commands: Dictionary = {}  # name -> Callable(args: Array)
var _run_id := 0
var _running := false
var _jobs_left := 0  # sequential thread + scheduled lines of the current run


func setup(evaluator: Evaluator, tree: SceneTree = null) -> void:
	_evaluator = evaluator
	_tree = tree


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


## Broadcasts a sequencer message: releases this run's @message("name") lines
## and emits sequencer_message. Game code may call this to gate sequences on
## gameplay (a door opening, a cutscene beat).
func send_message(message: String) -> void:
	if message == "":
		push_warning("Narrative sequencer: send_message() needs a non-empty name")
		return
	_release_message.emit(message)
	sequencer_message.emit(message)


## Stops the current run: no further commands of that run will execute.
func cancel_current() -> void:
	_run_id += 1
	_running = false
	_jobs_left = 0
	_release_message.emit("")  # wake waiters; they see the stale token and exit


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
	var sequential: Array = []
	var scheduled: Array = []
	for stmt in parsed.statements:
		if str(stmt[0]) == "timed" or str(stmt[0]) == "on_message":
			scheduled.append(stmt)
		else:
			sequential.append(stmt)
	var token := _run_id
	_running = true
	_jobs_left = 1 + scheduled.size()
	for stmt in scheduled:
		_execute_scheduled(stmt, token, label)  # not awaited: parallel
	_execute(sequential, token, label)


func _execute(statements: Array, token: int, label: String) -> void:
	for stmt in statements:
		if token != _run_id:
			return  # cancelled
		await _run_one(stmt, token, label)
		if token != _run_id:
			return
	_job_done(token, label)


## One scheduled line: wait for its time/message, then run it.
func _execute_scheduled(stmt: Array, token: int, label: String) -> void:
	if str(stmt[0]) == "on_message":
		var wanted := str(stmt[1])
		while true:
			var got: String = await _release_message
			if token != _run_id:
				return  # cancelled (or flushed by cancellation)
			if got == wanted:
				break
	else:  # timed
		var seconds := float(stmt[1])
		if seconds > 0.0:
			if _tree == null:
				push_warning("Narrative sequencer [%s]: @time needs a SceneTree (tree-less context?) — running immediately" % label)
			else:
				await _tree.create_timer(seconds).timeout
			if token != _run_id:
				return
	await _run_one(stmt[2], token, label)
	if token != _run_id:
		return
	_job_done(token, label)


## Executes one statement: ["call", name, args], optionally wrapped in
## ["notify", message, inner]. The notify message is broadcast when the line
## finishes — even when the command itself was skipped with a warning, so
## @message waiters can never deadlock on a typo.
func _run_one(stmt: Array, token: int, label: String) -> void:
	var notify := ""
	var call_ast: Array = stmt
	if str(stmt[0]) == "notify":
		notify = str(stmt[1])
		call_ast = stmt[2]
	var name: String = call_ast[1]
	if not _commands.has(name):
		push_warning("Narrative sequencer [%s]: unknown command '%s' — skipped" % [label, name])
	else:
		var args: Array = []
		var arg_failed := false
		for arg_ast in call_ast[2]:
			var result := _evaluator.evaluate(arg_ast)
			if not result.ok:
				push_warning("Narrative sequencer [%s]: argument error in '%s': %s — command skipped" % [label, name, result.error])
				arg_failed = true
				break
			args.append(result.value)
		if not arg_failed:
			var handler: Callable = _commands[name]
			if handler.is_valid():
				await handler.call(args)
				if token != _run_id:
					return
			else:
				push_warning("Narrative sequencer [%s]: command '%s' is no longer valid — skipped" % [label, name])
	if notify != "":
		send_message(notify)


func _job_done(token: int, label: String) -> void:
	if token != _run_id:
		return
	_jobs_left -= 1
	if _jobs_left <= 0:
		_running = false
		run_finished.emit(label)
