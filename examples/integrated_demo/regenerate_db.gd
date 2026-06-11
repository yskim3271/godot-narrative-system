extends SceneTree
## Regenerates demo_database.tres from db_builder.gd:
##   godot --headless --path . -s res://examples/integrated_demo/regenerate_db.gd

const DbBuilder := preload("db_builder.gd")
const OUTPUT := "res://examples/integrated_demo/demo_database.tres"


func _initialize() -> void:
	var db := DbBuilder.build()
	var issues := NarrativeValidator.new().validate(db)
	for issue in issues:
		print(NarrativeValidator.format_issue(issue))
	if NarrativeValidator.count_severity(issues, "error") > 0:
		printerr("regenerate_db: validation errors — not saving")
		quit(1)
		return
	var err := ResourceSaver.save(db, OUTPUT)
	print("regenerate_db: %s -> %s" % [error_string(err), OUTPUT])
	quit(0 if err == OK else 1)
