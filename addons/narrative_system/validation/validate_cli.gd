extends SceneTree
## Headless database validation:
##   godot --headless --path . -s res://addons/narrative_system/validation/validate_cli.gd -- --db=res://path/to/db.tres [--strict]
##
## Exit codes: 0 = no errors (warnings allowed unless --strict),
##             1 = validation errors, 2 = could not load the database.


func _initialize() -> void:
	var db_path := "res://narrative_database.tres"
	var strict := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--db="):
			db_path = arg.trim_prefix("--db=")
		elif arg == "--strict":
			strict = true

	if not ResourceLoader.exists(db_path):
		printerr("validate_cli: database not found: %s" % db_path)
		quit(2)
		return
	var db := load(db_path) as NarrativeDatabase
	if db == null:
		printerr("validate_cli: resource is not a NarrativeDatabase: %s" % db_path)
		quit(2)
		return

	var issues := NarrativeValidator.new().validate(db)
	for issue in issues:
		print(NarrativeValidator.format_issue(issue))
	var errors := NarrativeValidator.count_severity(issues, "error")
	var warnings := NarrativeValidator.count_severity(issues, "warning")
	print("validate_cli: %s — %d error(s), %d warning(s)" % [db_path, errors, warnings])
	quit(1 if errors > 0 or (strict and warnings > 0) else 0)
