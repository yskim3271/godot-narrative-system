@tool
extends RefCounted
## Save schema migration registry.
##
## When the save schema changes:
##  1. bump SAVE_VERSION in version.gd
##  2. add an entry here: from_version -> Callable(data) -> data(from_version+1)
##  3. add a regression test loading an old-version fixture
##
## The SaveManager chains steps until the data reaches the current version;
## a missing step refuses the load (never guess at unknown data).


## from_version (int) -> Callable(Dictionary) -> Dictionary
static func defaults() -> Dictionary:
	return {
		# Example for a future bump:
		# 1: func(data: Dictionary) -> Dictionary:
		# 	data["new_field"] = {}
		# 	return data,
	}
