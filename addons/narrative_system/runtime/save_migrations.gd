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
		# v1 -> v2: quest entries gained a "completions" counter (repeatable
		# quests, M3-2). v1 saves predate repeats, so every quest has 0.
		1: func(data: Dictionary) -> Dictionary:
			var quests: Variant = data.get("quests", {})
			if typeof(quests) == TYPE_DICTIONARY:
				for quest_id: String in quests:
					if typeof(quests[quest_id]) == TYPE_DICTIONARY and not quests[quest_id].has("completions"):
						quests[quest_id]["completions"] = 0
			return data,
	}
