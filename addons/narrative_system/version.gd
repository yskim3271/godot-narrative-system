@tool
extends RefCounted
## Central version constants for the Narrative System addon.
##
## VERSION follows semver and must match plugin.cfg.
## SAVE_VERSION is bumped only when the save JSON schema changes;
## every bump requires a migration entry in runtime/save_migrations.gd.

const VERSION := "1.1.0"
const SAVE_VERSION := 2
