extends RefCounted
## Built-in sequencer command library (the spec's 13 commands).
##
## Owned by the context (method Callables hold their RefCounted target only
## weakly — same lifetime rule as builtin_functions.gd); the context itself
## is captured through a WeakRef to stay cycle-free.
##
## Actor targets are nodes registered in the context's actor registry
## (via NarrativeActor children or register_actor()). Missing actors,
## players or animations warn and skip — sequences never crash a game.

var _ref: WeakRef


func install(context) -> void:
	_ref = weakref(context)
	var sequencer: NarrativeSequencer = context.sequencer
	sequencer.register_command("wait", cmd_wait)
	sequencer.register_command("play_animation", cmd_play_animation)
	sequencer.register_command("play_animation_wait", cmd_play_animation_wait)
	sequencer.register_command("play_audio", cmd_play_audio)
	sequencer.register_command("play_audio_wait", cmd_play_audio_wait)
	sequencer.register_command("move_camera", cmd_move_camera)
	sequencer.register_command("focus_camera", cmd_focus_camera)
	sequencer.register_command("emit_signal", cmd_emit_signal)
	sequencer.register_command("call_method", cmd_call_method)
	sequencer.register_command("show_actor", cmd_show_actor)
	sequencer.register_command("hide_actor", cmd_hide_actor)
	sequencer.register_command("set_expression", cmd_set_expression)
	sequencer.register_command("set_variable", cmd_set_variable)
	sequencer.register_command("start_quest", cmd_start_quest)
	sequencer.register_command("complete_quest", cmd_complete_quest)


func cmd_wait(args: Array) -> void:
	var ctx = _ctx()
	if ctx == null or ctx.scene_tree == null:
		push_warning("Narrative sequencer: wait() needs a SceneTree (headless context without tree?)")
		return
	var seconds := _num(args, 0, 0.0)
	if seconds > 0.0:
		await ctx.scene_tree.create_timer(seconds).timeout


func cmd_play_animation(args: Array) -> void:
	var player := _animation_player(_actor(args, 0))
	if player == null:
		return
	var animation := _str(args, 1)
	if not player.has_animation(animation):
		push_warning("Narrative sequencer: play_animation — no animation '%s'" % animation)
		return
	player.play(animation)


func cmd_play_animation_wait(args: Array) -> void:
	var player := _animation_player(_actor(args, 0))
	if player == null:
		return
	var animation := _str(args, 1)
	if not player.has_animation(animation):
		push_warning("Narrative sequencer: play_animation_wait — no animation '%s'" % animation)
		return
	player.play(animation)
	await player.animation_finished


func cmd_play_audio(args: Array) -> void:
	_start_audio(args)


func cmd_play_audio_wait(args: Array) -> void:
	var player := _start_audio(args)
	if player == null or player.stream == null:
		return
	var ctx = _ctx()
	if ctx == null or ctx.scene_tree == null:
		return
	# The headless dummy audio driver may never emit `finished`;
	# waiting for the stream length is reliable everywhere.
	await ctx.scene_tree.create_timer(maxf(player.stream.get_length(), 0.01)).timeout


func cmd_move_camera(args: Array) -> void:
	var camera := _camera_2d()
	if camera == null:
		return
	await _tween_camera(camera, Vector2(_num(args, 0, 0.0), _num(args, 1, 0.0)), _num(args, 2, 0.5))


func cmd_focus_camera(args: Array) -> void:
	var camera := _camera_2d()
	if camera == null:
		return
	var actor := _actor(args, 0)
	if actor == null:
		return
	if not actor is Node2D:
		push_warning("Narrative sequencer: focus_camera — actor '%s' is not a Node2D" % _str(args, 0))
		return
	await _tween_camera(camera, (actor as Node2D).global_position, _num(args, 1, 0.5))


func cmd_emit_signal(args: Array) -> void:
	var ctx = _ctx()
	if ctx == null:
		return
	if args.is_empty():
		push_warning("Narrative sequencer: emit_signal needs an event name")
		return
	ctx.sequencer.sequence_event.emit(str(args[0]), args.slice(1))


func cmd_call_method(args: Array) -> void:
	var actor := _actor(args, 0)
	if actor == null:
		return
	var method := _str(args, 1)
	if not actor.has_method(method):
		push_warning("Narrative sequencer: call_method — '%s' has no method '%s'" % [actor.name, method])
		return
	actor.callv(method, args.slice(2))


func cmd_show_actor(args: Array) -> void:
	_set_actor_visible(args, true)


func cmd_hide_actor(args: Array) -> void:
	_set_actor_visible(args, false)


func cmd_set_expression(args: Array) -> void:
	var ctx = _ctx()
	if ctx != null and ctx.runner != null:
		ctx.runner.notify_expression(_str(args, 0), _str(args, 1))


func cmd_set_variable(args: Array) -> void:
	var ctx = _ctx()
	if ctx == null or args.size() < 2:
		push_warning("Narrative sequencer: set_variable(name, value) needs two arguments")
		return
	var result: Dictionary = ctx.state.set_value(str(args[0]), args[1])
	if not result.ok:
		push_warning("Narrative sequencer: set_variable — %s" % str(result.error))


func cmd_start_quest(args: Array) -> void:
	var ctx = _ctx()
	if ctx != null and ctx.quests != null:
		ctx.quests.start_quest(_str(args, 0))


func cmd_complete_quest(args: Array) -> void:
	var ctx = _ctx()
	if ctx != null and ctx.quests != null:
		ctx.quests.complete_quest(_str(args, 0))


# --- helpers ---


func _ctx():
	return _ref.get_ref() if _ref != null else null


func _str(args: Array, index: int, fallback := "") -> String:
	return str(args[index]) if index < args.size() else fallback


func _num(args: Array, index: int, fallback: float) -> float:
	if index < args.size() and (typeof(args[index]) == TYPE_INT or typeof(args[index]) == TYPE_FLOAT):
		return float(args[index])
	return fallback


func _actor(args: Array, index: int) -> Node:
	var ctx = _ctx()
	if ctx == null:
		return null
	var actor_id := _str(args, index)
	var node: Node = ctx.get_actor(actor_id)
	if node == null:
		push_warning("Narrative sequencer: unknown actor '%s' (register it with a NarrativeActor node)" % actor_id)
	return node


func _animation_player(actor: Node) -> AnimationPlayer:
	if actor == null:
		return null
	if actor is AnimationPlayer:
		return actor
	for child in actor.find_children("*", "AnimationPlayer", true, false):
		return child
	push_warning("Narrative sequencer: actor '%s' has no AnimationPlayer" % actor.name)
	return null


func _start_audio(args: Array) -> Node:
	var actor := _actor(args, 0)
	if actor == null:
		return null
	var player: Node = null
	if actor is AudioStreamPlayer or actor is AudioStreamPlayer2D or actor is AudioStreamPlayer3D:
		player = actor
	else:
		for cls in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
			var found := actor.find_children("*", cls, true, false)
			if not found.is_empty():
				player = found[0]
				break
	if player == null:
		push_warning("Narrative sequencer: actor '%s' has no AudioStreamPlayer" % actor.name)
		return null
	var path := _str(args, 1)
	if path != "":
		if not path.begins_with("res://"):
			push_warning("Narrative sequencer: play_audio only loads res:// paths, got '%s'" % path)
			return null
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("Narrative sequencer: '%s' is not an AudioStream" % path)
			return null
		player.stream = stream
	if player.stream == null:
		push_warning("Narrative sequencer: no stream to play on '%s'" % actor.name)
		return null
	player.play()
	return player


func _set_actor_visible(args: Array, value: bool) -> void:
	var actor := _actor(args, 0)
	if actor == null:
		return
	if "visible" in actor:
		actor.visible = value
	else:
		push_warning("Narrative sequencer: actor '%s' has no 'visible' property" % actor.name)


func _camera_2d() -> Camera2D:
	var ctx = _ctx()
	if ctx == null or ctx.scene_tree == null:
		return null
	var camera: Camera2D = ctx.scene_tree.root.get_camera_2d()
	if camera == null:
		push_warning("Narrative sequencer: no active Camera2D")
	return camera


func _tween_camera(camera: Camera2D, target: Vector2, duration: float) -> void:
	var ctx = _ctx()
	if ctx == null or ctx.scene_tree == null:
		return
	if duration <= 0.0:
		camera.global_position = target
		return
	var tween: Tween = ctx.scene_tree.create_tween()
	tween.tween_property(camera, "global_position", target, duration)
	await tween.finished
