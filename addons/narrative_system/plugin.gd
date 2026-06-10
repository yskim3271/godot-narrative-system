@tool
extends EditorPlugin
## Editor integration for the Narrative System.
##
## - _enable_plugin()/_disable_plugin(): registers/removes the "Narrative"
##   autoload and ensures the narrative_system/database_path project setting.
## - _enter_tree()/_exit_tree(): adds/removes the bottom panel (database
##   overview + validation + CSV tools).
##
## The runtime never depends on this plugin: with the plugin disabled, games
## can register the autoload manually (docs/getting_started.md) — editor
## panels likewise never reference the autoload.

const AUTOLOAD_NAME := "Narrative"
const AUTOLOAD_PATH := "res://addons/narrative_system/runtime/narrative.gd"
const SETTING_DATABASE_PATH := "narrative_system/database_path"

const PanelScript := preload("editor/narrative_panel.gd")

var _panel: Control


func _enter_tree() -> void:
	_ensure_project_setting()
	_panel = PanelScript.new()
	add_control_to_bottom_panel(_panel, "Narrative")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null


func _enable_plugin() -> void:
	_ensure_project_setting()
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _ensure_project_setting() -> void:
	if not ProjectSettings.has_setting(SETTING_DATABASE_PATH):
		ProjectSettings.set_setting(SETTING_DATABASE_PATH, "")
	ProjectSettings.set_initial_value(SETTING_DATABASE_PATH, "")
	ProjectSettings.add_property_info({
		"name": SETTING_DATABASE_PATH,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres",
	})
