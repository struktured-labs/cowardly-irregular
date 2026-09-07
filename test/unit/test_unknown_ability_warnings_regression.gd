extends GutTest

## tick 26 caught the print-only fallthrough in _execute_meta_ability.
## _execute_ability had TWO more sites with the same shape:
##   - JobSystem.get_ability returns {} → "Unknown ability <id>"
##   - match ability_type has no matching arm → "Unknown ability type <t>"
## Both consumed the caster's turn (AP cost paid) and did nothing,
## with only a print to flag the problem. Print is invisible to GUT,
## CI logs, and any push_warning-aware audit.
##
## Fix: push_warning both branches, naming the offending strings so
## the dev knows WHICH ability id / type to fix.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(BATTLE_MANAGER)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_unknown_ability_id_pushes_warning() -> void:
	var body := _body_of("_execute_ability")
	# Anchor on the literal text — search-quote escaping was a tick 26
	# pitfall.
	var idx := body.find("Unknown ability %s")
	assert_gt(idx, -1, "unknown-ability print must exist as anchor")
	var window := body.substr(idx, 400)
	assert_true(window.contains("push_warning"),
		"unknown ability_id must push_warning so CI / test runs catch the typo / stale alias")


func test_unknown_ability_type_pushes_warning() -> void:
	var body := _body_of("_execute_ability")
	var idx := body.find("Unknown ability type:")
	assert_gt(idx, -1, "unknown-ability-type print must exist as anchor")
	var window := body.substr(idx, 400)
	assert_true(window.contains("push_warning"),
		"unhandled ability_type must push_warning — a new type added to abilities.json without a handler silently consumed turns before")


func test_warnings_name_the_offender() -> void:
	# Each warning must include the offending string so the dev can
	# grep for it. Vague "ability resolution failed" is unactionable.
	var body := _body_of("_execute_ability")
	# Ability-id warning must reference both ability_id and caster.
	var ability_warning_idx := body.find("push_warning(\"BattleManager._execute_ability: unknown ability_id")
	assert_gt(ability_warning_idx, -1, "ability_id warning must exist and name itself")
	var ability_window := body.substr(ability_warning_idx, 200)
	assert_true(ability_window.contains("ability_id") and ability_window.contains("caster"),
		"unknown-ability warning must reference both ability_id and the caster — gives dev grep targets")
	# Type warning must reference both ability_type and ability id.
	var type_warning_idx := body.find("push_warning(\"BattleManager._execute_ability: unhandled ability_type")
	assert_gt(type_warning_idx, -1, "ability_type warning must exist and name itself")
	var type_window := body.substr(type_warning_idx, 200)
	assert_true(type_window.contains("ability_type") and type_window.contains("ability"),
		"unhandled-type warning must reference both ability_type and the ability id")
