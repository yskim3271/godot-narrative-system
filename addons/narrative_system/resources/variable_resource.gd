class_name NarrativeVariable
extends Resource
## Declaration of a narrative variable: id, type and default value.
##
## Runtime values live in NarrativeState; this resource only declares the
## variable and its initial value. The per-type default fields exist because
## Variant cannot be @export-ed directly — only the field matching [member type]
## is used.

enum Type { BOOL, INT, FLOAT, STRING }

## Unique id used in DSL expressions (charset: [a-zA-Z0-9_.], dots allowed
## for namespacing like "player.gold").
@export var id := ""
## Value type. Assignments at runtime are coerced to this type; incompatible
## assignments are skipped with a warning.
@export var type: Type = Type.STRING
## Included in save files (set false for derived/session-only values).
@export var persistent := true

@export_group("Default value (use the field matching Type)")
@export var default_bool := false
@export var default_int := 0
@export var default_float := 0.0
@export var default_string := ""


## The default value according to [member type].
func get_default() -> Variant:
	match type:
		Type.BOOL:
			return default_bool
		Type.INT:
			return default_int
		Type.FLOAT:
			return default_float
		_:
			return default_string
