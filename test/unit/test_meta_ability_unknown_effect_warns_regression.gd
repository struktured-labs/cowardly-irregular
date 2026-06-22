extends GutTest

## Symmetry with the _execute_support_ability loud-fail (line ~3026):
## _execute_meta_ability used to print-only on unknown meta_effect.
## Print goes to stdout, vanishes from GUT runs and CI logs. A typo
## in abilities.json would silently consume AP and do nothing on every
## cast — exactly the silent-failure class CLAUDE.md calls out as the
## project's worst.
##
## Fix: push_warning the unknown branch so it shows up as a [WARNING]
## line in test runs and surfaces in any push_warning-aware audit.

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


func test_unknown_meta_effect_pushes_warning() -> void:
	var body := _body_of("_execute_meta_ability")
	# Anchor on the literal text inside the print so the search doesn't
	# trip on whitespace between the opening quote and the message.
	var idx := body.find("Unknown meta effect:")
	assert_gt(idx, -1, "unknown-effect print must exist as anchor")
	# The push_warning must be near the print, not in some unrelated branch.
	var window := body.substr(idx, 400)
	assert_true(window.contains("push_warning"),
		"unknown meta_effect must push_warning so CI / test runs catch it (print-only is invisible to GUT)")


func test_unknown_meta_effect_warning_names_the_offender() -> void:
	# The warning text must include the actual meta_effect string AND
	# the ability id so the dev knows WHICH ability needs fixing.
	var body := _body_of("_execute_meta_ability")
	var idx := body.find("push_warning(\"BattleManager._execute_meta_ability")
	assert_gt(idx, -1, "warning anchor must exist")
	var window := body.substr(idx, 200)
	assert_true(window.contains("meta_effect") and window.contains("ability"),
		"warning must reference both meta_effect (which string was unknown) and ability id (which entry to fix)")


func test_support_ability_already_warns_for_symmetry() -> void:
	# Symmetry check: the sibling _execute_support_ability already did
	# this. If a future cleanup pulls IT, the symmetry justification for
	# tick 26 still holds because the precedent was set elsewhere.
	var body := _body_of("_execute_support_ability")
	assert_true(body.contains("push_warning"),
		"_execute_support_ability must keep its unknown-effect push_warning — the loud-fail pattern this fix mirrors")
