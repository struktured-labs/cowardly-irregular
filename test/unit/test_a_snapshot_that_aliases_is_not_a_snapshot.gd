extends GutTest

## `autobattle_profiles.snapshot()` deep-copies, and NOTHING pinned that.
##
## GDScript Dictionaries are reference types, so `_saved[k] = live[k]` captures the OBJECT,
## not its value — a "snapshot" that follows every later mutation, and a restore that puts
## the mutated object back while reporting success. A sibling lane found exactly that shape
## in their own snapshot helper tonight.
##
## The blast radius is why this is pinned rather than commented: 17 test files use this
## helper, plus two sibling helpers (autogrind_state, sound_state). A change from
## `.duplicate(true)` to `.duplicate()` breaks teardown in all of them SILENTLY — every
## after_each still runs, still reports nothing, and restores state that moved.
##
## Mutation-verified: `.duplicate()` reds this arm naming the aliased field; the deep copy
## passes. The nesting matters — a shallow copy is correct at the TOP level, so an arm that
## only planted a top-level key would pass under both and pin nothing.

const Profiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _abs = null


func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")


func after_each() -> void:
	if _abs != null:
		(_abs.character_profiles as Dictionary).erase("zz_alias_probe")


func test_a_nested_mutation_does_not_reach_the_snapshot() -> void:
	var live: Dictionary = _abs.character_profiles
	live["zz_alias_probe"] = {"profiles": [{"name": "Original", "rules": []}]}
	var snap: Dictionary = Profiles.snapshot(_abs)
	assert_true(snap.has("zz_alias_probe"),
		"CONTROL: the snapshot must have captured the planted key, or this arm tests nothing")
	## NESTED, deliberately: a shallow duplicate is already correct one level up.
	(live["zz_alias_probe"]["profiles"][0] as Dictionary)["name"] = "MUTATED"
	assert_eq(str((snap["zz_alias_probe"]["profiles"][0] as Dictionary)["name"]), "Original",
		"the snapshot ALIASES live state — restore() would put the MUTATED object back, and every after_each using this helper would report success while leaking")
