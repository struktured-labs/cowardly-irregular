extends GutTest

## Playtest 2026-07-14 (round 2): "Target no longer valid!" trying to bring
## Bard back to life with Phoenix Down.
##
## Root: v3.33.150 added revive-eligibility to the MENU BUILD (so KO'd
## allies show up in the Phoenix Down target list) — but the EXECUTE branch
## at BattleCommandMenu:913 still gated on `target.is_alive`, torching the
## intent at the last mile. Menu offered the target, execute rejected it.
##
## Fix: execute path mirrors the menu-build gate — item.effects.revive
## admits KO'd allies for ally targets.


func test_execute_item_gate_admits_ko_ally_when_item_revives() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	# Anchor on the exact log-message right before the fix so a rewrite
	# would move the anchor and force a look here.
	var i := src.find("BattleManager.player_item(i_id, [target])")
	assert_gt(i, -1)
	# Look at the ~400 chars leading up to the call.
	var window := src.substr(maxi(0, i - 400), 500)
	assert_true("can_revive" in window,
		"item-execute path must derive a can_revive flag from item.effects.revive — bare `target.is_alive` gate torches Phoenix Down on KO'd allies")
	assert_true("effects" in window and "revive" in window,
		"revive detection must consult ItemSystem.get_item(...).effects.revive")
	assert_false("if is_instance_valid(target) and target.is_alive:\n\t\t\t\tBattleManager.player_item" in window,
		"the raw is_alive gate is the bug — must be replaced by a revive-aware check")
