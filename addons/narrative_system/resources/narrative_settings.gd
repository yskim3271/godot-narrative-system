@tool
class_name NarrativeSettings
extends Resource
## Global behavior settings, stored inside a [NarrativeDatabase].
##
## Pure data — no logic, no @tool. Runtime systems read these once at
## context creation.

## Language used when no save/explicit language is set.
@export var default_language := "en"
## Language tried when a localization key is missing in the current language.
@export var fallback_language := "en"
## Mirror language changes into TranslationServer.set_locale() so engine-side
## strings (tr()) follow the narrative language.
@export var sync_godot_locale := false
## Maximum entries kept in the dialogue history ring buffer (and in saves).
@export var history_limit := 200
## Safety cap for condition-skip chains inside one node transition.
@export var max_node_hops := 64
## Collect unresolved localization keys at runtime (queryable for tooling).
@export var collect_missing_keys := true
## When true, assigning to a variable that is not declared in the database
## logs a warning (the assignment still creates a transient variable).
@export var strict_variables := false
## Function names registered by game code at runtime. The validator cannot
## see runtime registrations, so names listed here are downgraded from
## "unknown function" errors to warnings.
@export var declared_external_functions: PackedStringArray = []
